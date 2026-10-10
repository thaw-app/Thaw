//
//  MenuBarSearchPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import Observation
import SwiftUI
import ThawCapture
import ThawUI

extension EnvironmentValues {
    @Entry var menuBarSearchPanel: MenuBarSearchPanel?
}

/// Floating panel hosting the menu bar item search, in whichever face
/// SearchPresentation asks for. Dismissed on resign-key, an outside click,
/// or a space or display change.
final class MenuBarSearchPanel: NSPanel {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarSearchPanel")

    /// Must match the glass effect the hosted view draws.
    static let cornerRadius: CGFloat = ThawRadius.panel

    /// Written only at the top of show(on:), so a preference flipped while
    /// the panel is up cannot make close() save the wrong face's frame.
    private(set) var presentation: SearchPresentation = .inspector

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// A click right after a move is that move's tail, not a dismissal.
    private var moveActivity: MoveOperationTracker?

    private var cacheTask: Task<Void, Never>?

    /// Retargets the real menu bar spotlight to the highlighted row.
    private var selectionObservationTask: Task<Void, Never>?

    /// Lights the selected item after a short delay; replaced on each
    /// selection change.
    private var spotlightTask: Task<Void, Never>?

    /// Whether the agent confirmed the highlight, so teardown releases only
    /// a spotlight that landed.
    private var isSpotlighted = false

    /// Captured up front so endSpotlight() releases the right item after the
    /// selection has moved on.
    private var spotlightedName: String?

    private let model = MenuBarSearchModel()

    /// The actions button the actions menu hangs from. Weak because the
    /// hosting view owns it.
    weak var itemActionsAnchor: NSView?

    /// While the actions menu tracks, outside clicks and losing key must not
    /// dismiss the panel from under it.
    private var isPresentingItemActions = false

    /// Only the inspector's "Remember last search" toggle can keep the query;
    /// the launcher always opens empty.
    private var keepsQuery: Bool {
        presentation.honorsKeepSearchToggle && Defaults.bool(forKey: .rememberSearchQuery)
    }

    private lazy var outsideClickMonitor = EventMonitor.universal(for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
        guard let self, let appState, event.window !== self, !isPresentingItemActions else {
            return event
        }
        if moveActivity?.occurred(within: .seconds(1)) != true {
            close()
        }
        return event
    }

    /// ⌘, opens Settings, ⌘E renames, ⌘K opens the actions menu, ⌘1 to ⌘3
    /// move the item between sections, ⌘L opens its layout pane.
    private lazy var shortcutMonitor = EventMonitor.universal(for: [.keyDown]) { [weak self] event in
        guard let self, Modifiers(nsEventFlags: event.modifierFlags) == .command else {
            return event
        }
        let keyCode = KeyCode(rawValue: Int(event.keyCode))
        if keyCode == .comma {
            close()
            appState?.activate(withPolicy: .regular)
            appState?.openWindow(.settings)
            return nil
        }
        if keyCode == .e, presentation.allowsRename {
            beginRenamingSelection()
            return nil
        }
        // With no highlighted row these keys pass through.
        guard
            presentation.allowsItemManagement,
            model.renameSession == nil,
            let appState,
            selectedItem != nil
        else {
            return event
        }
        if keyCode == .k {
            presentItemActions()
            return nil
        }
        if keyCode == .l {
            close()
            MenuBarSearchItemActions.openSettings(appState: appState)
            return nil
        }
        if let index = [KeyCode.one, .two, .three].firstIndex(of: keyCode) {
            moveSelection(toDestinationAt: index)
            return nil
        }
        return event
    }

    override var canBecomeKey: Bool {
        true
    }

    /// Tracked so a showing in the same mode does not rebuild the subscriptions.
    private var isSamplingMenuBarColor = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .titled, .fullSizeContentView, .nonactivatingPanel,
                .utilityWindow,
            ],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [
            .fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace,
        ]
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        // No setFrameAutosaveName: frames are saved per display by hand.
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        selectionObservationTask?.cancel()
        endSpotlight()
    }

    @objc private func panelResignedKey(_: Notification) {
        // The actions menu takes focus; menuDidClose(_:) re-tests key afterwards.
        guard !isPresentingItemActions else {
            return
        }
        close()
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        moveActivity = appState.itemManager.moveActivity

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in self?.appearance = appearance }
            .store(in: &cancellables)

        // Save the frame if the app quits with the panel open. The mode is
        // tested when it fires, since it can change after launch.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self, presentation.persistsFrame, let screen else { return }
                saveFrameForDisplay(screen)
            }
            .store(in: &cancellables)

        // A space or display change invalidates the position, so close.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.activeSpaceDidChangeNotification
            ),
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        )
        .sink { [weak self] _ in self?.close() }
        .store(in: &cancellables)

        // The mode is unknown until the first showing, so this runs in every
        // mode and retargetSpotlight() declines where it does not apply.
        observeSelectionForSpotlight()
    }

    /// By window when the row knew one, otherwise by tag.
    private func cachedItem(withTag tag: MenuBarItemTag, windowID: CGWindowID?) -> MenuBarItem? {
        guard let itemManager = appState?.itemManager else {
            return nil
        }
        if let windowID {
            return itemManager.managedItem(withWindowID: windowID)
        }
        return itemManager.managedItem(withTag: tag)
    }

    /// The item a search list row stands for, if it is still in the cache.
    func cachedItem(for selection: MenuBarSearchModel.ItemID) -> MenuBarItem? {
        guard case let .item(tag, windowID) = selection else {
            return nil
        }
        return cachedItem(withTag: tag, windowID: windowID)
    }

    // MARK: Selection spotlight

    /// The selection-driven counterpart of LayoutBarItemView's hover spotlight.
    /// Deduped by hand, since Observations redelivers the current value first.
    private func observeSelectionForSpotlight() {
        selectionObservationTask?.cancel()
        selectionObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let changes = Observations { self.model.selection }
            var previous: MenuBarSearchModel.ItemID?
            for await selection in changes {
                guard selection != previous else { continue }
                previous = selection
                retargetSpotlight()
            }
        }
    }

    private func retargetSpotlight() {
        endSpotlight()
        guard presentation.spotlightsSelection,
              isVisible,
              let selection = model.selection,
              let item = cachedItem(for: selection),
              // Control items and untitled items have no AX title to address.
              !item.isControlItem,
              let title = item.title, !title.isEmpty
        else {
            return
        }
        scheduleSpotlight(name: title)
    }

    /// Shorter delay than hover's, since a selection change is deliberate.
    private func scheduleSpotlight(name: String) {
        guard let spotlighting = MenuBarPresentationProvider.itemSpotlighting,
              spotlighting.isSupported
        else {
            return
        }
        spotlightedName = name
        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let landed = await spotlighting.setItemSpotlighted(true, forItemNamed: name)
            guard let self, !Task.isCancelled else {
                // Superseded mid-call: pair the true with a false.
                if landed {
                    Task { await spotlighting.setItemSpotlighted(false, forItemNamed: name) }
                }
                return
            }
            self.isSpotlighted = landed
        }
    }

    /// Pairs every true sent to the agent with a false.
    private func endSpotlight() {
        spotlightTask?.cancel()
        spotlightTask = nil
        defer { spotlightedName = nil }
        guard isSpotlighted, let name = spotlightedName,
              let spotlighting = MenuBarPresentationProvider.itemSpotlighting
        else {
            return
        }
        isSpotlighted = false
        Task { await spotlighting.setItemSpotlighted(false, forItemNamed: name) }
    }

    // MARK: Item actions

    /// The item the highlighted row stands for, if it is still in the cache.
    var selectedItem: MenuBarItem? {
        guard let selection = model.selection else {
            return nil
        }
        return cachedItem(for: selection)
    }

    /// A menu, not buttons, because group destinations have unknown length;
    /// it also matches the layout editor's right-click menu.
    func presentItemActions() {
        guard
            presentation.allowsItemManagement,
            let appState,
            let anchor = itemActionsAnchor,
            let item = selectedItem
        else {
            return
        }

        let menu = MenuBarSearchItemActions.menu(for: item, appState: appState) { [weak self] in
            guard let self else { return }
            close()
            MenuBarSearchItemActions.openSettings(appState: appState)
        }
        menu.delegate = self
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    /// ⌘1 to ⌘3. A disabled section's number does nothing rather than
    /// renumbering the others.
    func moveSelection(toDestinationAt index: Int) {
        guard
            presentation.allowsItemManagement,
            let appState,
            let item = selectedItem
        else {
            return
        }
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState)
        guard destinations.indices.contains(index), let section = destinations[index] else {
            return
        }
        MenuBarSearchItemActions.move(item, to: section, appState: appState)
    }

    // MARK: Rename

    func beginRenamingSelection() {
        guard
            presentation.allowsRename,
            case let .item(tag, windowID)? = model.selection,
            let item = cachedItem(withTag: tag, windowID: windowID)
        else {
            return
        }
        model.renameSession = .init(tag: tag, windowID: windowID, draft: item.customName ?? "")
    }

    /// An all-whitespace draft removes the custom name.
    func commitRename() {
        guard let session = model.renameSession else {
            return
        }
        model.renameSession = nil

        guard let item = cachedItem(withTag: session.tag, windowID: session.windowID) else {
            Self.diagLog.error("Cannot save custom name, no matching item")
            return
        }
        Self.diagLog.debug("Saving custom name for tag: \(session.tag)")

        var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        let newName = session.draft.trimmingCharacters(in: .whitespaces)
        if newName.isEmpty {
            names.removeValue(forKey: item.uniqueIdentifier)
        } else {
            names[item.uniqueIdentifier] = newName
        }
        Defaults.set(names, forKey: .menuBarItemCustomNames)
        // A Defaults write is not observed. Reassigning displayedItems is,
        // since the @Observable setter has no equality check, so rows re-render.
        // Routed through a local so it does not read as a typo'd x = x.
        let itemsToRerender = model.displayedItems
        model.displayedItems = itemsToRerender
    }

    // MARK: Presentation

    /// Presents the panel, defaulting to the screen under the pointer.
    func show(on screen: NSScreen? = nil) {
        guard let appState else {
            return
        }
        guard let screen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main else {
            Self.diagLog.error("Missing screen for \(presentation.logLabel)")
            return
        }

        // The one place the mode is adopted.
        let mode = appState.settings.advanced.menuBarSearchPresentation
        let modeChanged = mode != presentation
        presentation = mode
        updateMenuBarColorSampling()

        if !keepsQuery {
            model.searchText = ""
        }

        // Set up front: the cache refresh below reads it to decide whether
        // live capture is worth running.
        appState.navigationState.isSearchPresented = true

        // Reuse the hosting view, since a new SwiftUI graph per show
        // accumulates (see ThawBarHostingView.update). A mode change rebuilds
        // it: intrinsicContentSize is read before a reused host lays out.
        let rootView = MenuBarSearchRootView(
            appState: appState,
            model: model,
            displayID: screen.displayID,
            panel: self,
            presentation: presentation
        )
        let hostingView: MenuBarSearchHostingView
        if !modeChanged, let existing = contentView as? MenuBarSearchHostingView {
            existing.rootView = rootView
            hostingView = existing
        } else {
            hostingView = MenuBarSearchHostingView(rootView: rootView)
        }
        let size = hostingView.intrinsicContentSize
        hostingView.setFrameSize(size)
        setFrame(placementFrame(on: screen, size: size), display: false)

        contentView = hostingView
        // Match the glass effect's corner radius and curve.
        contentView?.layer?.cornerRadius = Self.cornerRadius
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.masksToBounds = true
        makeKeyAndOrderFront(nil)

        outsideClickMonitor.start()
        shortcutMonitor.start()

        guard presentation.warmsCachesOnShow else {
            return
        }
        // Cancelled in close() to avoid holding appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState] in
            guard let appState else { return }
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.recaptureIfWarranted()
            appState.imageCache.logCacheStatus("Search panel opened")
        }
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    override func close() {
        if presentation.persistsFrame, isVisible, let screen, contentView != nil {
            saveFrameForDisplay(screen)
        }
        cacheTask?.cancel()
        cacheTask = nil
        endSpotlight()
        if !keepsQuery {
            model.searchText = ""
        }
        model.renameSession = nil
        super.close()
        // Hosting view retained deliberately; show() repoints it.
        outsideClickMonitor.stop()
        shortcutMonitor.stop()
        appState?.navigationState.isSearchPresented = false
        MemoryReclaimer.scheduleRelief(reason: "\(presentation.logLabel) closed")
    }

    /// Escape backs out one layer at a time: rename, then query, then panel.
    override func cancelOperation(_: Any?) {
        if model.renameSession != nil {
            model.renameSession = nil
        } else if model.searchText != "", !keepsQuery {
            model.searchText = ""
        } else {
            close()
        }
    }

    // MARK: Per-display frame persistence

    /// Nil when the display has no resolvable UUID.
    private func frameDefaultsKey(for screen: NSScreen) -> String? {
        guard let uuidString = Bridging.getDisplayUUIDString(for: screen.displayID) else {
            return nil
        }
        return "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"
    }

    private func saveFrameForDisplay(_ screen: NSScreen) {
        guard isVisible, contentView != nil else {
            return
        }

        let currentFrame = frame
        let actualScreen = NSScreen.screens.first { $0.visibleFrame.intersects(currentFrame) } ?? screen

        guard let keyString = frameDefaultsKey(for: actualScreen) else {
            return
        }

        // Relative to the display's visible frame.
        let visibleFrame = actualScreen.visibleFrame
        let relativeFrame = CGRect(
            x: currentFrame.minX - visibleFrame.minX,
            y: currentFrame.minY - visibleFrame.minY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        UserDefaults.standard.set(relativeFrame.dictionaryRepresentation as NSDictionary, forKey: keyString)
    }

    private func loadFrameForDisplay(_ screen: NSScreen) -> CGRect? {
        guard
            let keyString = frameDefaultsKey(for: screen),
            let frameDict = UserDefaults.standard.dictionary(forKey: keyString)
        else {
            return nil
        }
        return CGRect(dictionaryRepresentation: frameDict as CFDictionary)
    }

    private func placementFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        switch presentation.placement {
        case .remembered: rememberedFrame(on: screen, size: size)
        case .centered: launcherFrame(on: screen, size: size)
        case .nearPointer: assistedFrame(on: screen, size: size)
        }
    }

    /// Anchored to the pointer; see AssistedPanelPlacement.
    private func assistedFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        AssistedPanelPlacement.frame(
            near: NSEvent.mouseLocation,
            in: screen.visibleFrame,
            size: size
        )
    }

    /// The saved spot clamped to the visible area, or dead center.
    private func rememberedFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        let visibleFrame = screen.visibleFrame

        guard let savedFrame = loadFrameForDisplay(screen) else {
            let centered = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
            return CGRect(origin: centered, size: size)
        }

        // Saved origins are relative to the display's visible frame.
        let origin = CGPoint(
            x: min(max(savedFrame.minX + visibleFrame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(savedFrame.minY + visibleFrame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    /// Slightly above center, like Spotlight.
    private func launcherFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        let visible = screen.visibleFrame
        let originX = visible.midX - size.width / 2
        let originY = visible.midY - size.height / 2 + visible.height * 0.12
        return CGRect(
            x: originX.rounded(),
            y: min(originY, visible.maxY - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }

    // MARK: Menu bar color sampling

    /// Sampling costs a screen capture per showing, so only modes that preview
    /// items over the bar color do it. Switched per showing, since the mode can change.
    private func updateMenuBarColorSampling() {
        let wanted = presentation.samplesMenuBarColor
        guard wanted != isSamplingMenuBarColor else {
            return
        }
        isSamplingMenuBarColor = wanted
        if wanted {
            model.attach(to: self)
        } else {
            model.detach()
        }
    }
}

// MARK: - Actions menu tracking

extension MenuBarSearchPanel: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        isPresentingItemActions = true
    }

    func menuDidClose(_: NSMenu) {
        isPresentingItemActions = false
        // Apply a dismissal suppressed while the menu was up. Tested now, not
        // remembered, since Escape closes the menu without the panel losing key.
        if !isKeyWindow {
            close()
        }
    }
}
