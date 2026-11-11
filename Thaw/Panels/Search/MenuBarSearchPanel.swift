//
//  MenuBarSearchPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Combine
import MenuBarModel
import Observation
import SwiftUI
import ThawCapture
import ThawUI

extension EnvironmentValues {
    @Entry var menuBarSearchPanel: MenuBarSearchPanel?
}

/// The menu bar search, drawn as Floe's launcher. Closes on losing key, an
/// outside click, or a space or display change.
final class MenuBarSearchPanel: NSPanel {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarSearchPanel")

    /// The layout of this showing, adopted in show(on:). Keyboard tests set it
    /// to exercise the compact faces without showing the panel.
    var presentation: SearchPresentation = .extended

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// A click right after a move is that move's tail, not a dismissal.
    private var moveActivity: MoveOperationTracker?

    let model = MenuBarSearchModel()

    /// The display the panel opened on, where an opened item is clicked.
    private var displayID: CGDirectDisplayID?

    /// Refreshes the item pictures after the panel shows; cancelled on close.
    private var pictureRefresh: Task<Void, Never>?

    /// The actions button the actions menu hangs from. Weak because the
    /// hosting view owns it.
    weak var itemActionsAnchor: NSView?

    /// While the actions menu tracks, outside clicks and losing key must not
    /// dismiss the panel from under it.
    private var isPresentingItemActions = false

    /// Every face has the action bar, so its "Remember last search" applies to all.
    private var keepsQuery: Bool {
        Defaults.bool(forKey: .rememberSearchQuery)
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

    /// The panel's keys; see handleKeyDown(_:).
    private lazy var shortcutMonitor = EventMonitor.universal(for: [.keyDown]) { [weak self] event in
        Self.monitoredKey(event, panel: self)
    }

    /// The handler's answer, nil for a key it took, or the event itself once the panel is gone.
    static func monitoredKey(_ event: NSEvent, panel: MenuBarSearchPanel?) -> NSEvent? {
        guard let panel else { return event }
        return panel.handleKeyDown(event)
    }

    /// Set before the query field is refocused after a rename, so it gets
    /// the insertion point at the end rather than all its text selected.
    var placesQueryCaretAtEnd = false

    override var canBecomeKey: Bool {
        true
    }

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
        // The glass draws its own depth inside the margin SearchPanelGeometry
        // leaves; AppKit's shadow would outline the window's square corners.
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func panelResignedKey(_: Notification) {
        // The actions menu takes focus; menuDidClose(_:) re-tests key afterwards.
        guard !isPresentingItemActions else {
            return
        }
        close()
    }

    func performSetup(with appState: AppState, displayInvalidations: some Publisher<Void, Never>) {
        self.appState = appState
        moveActivity = appState.itemManager.moveActivity

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in self?.appearance = appearance }
            .store(in: &cancellables)

        // A display change closes at the posting, while the frame still belongs to its display.
        DisplayEnvironment.spaceOrDisplayChanges(merging: displayInvalidations)
            .sink { [weak self] in self?.close() }
            .store(in: &cancellables)
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
        cachedItem(withTag: selection.tag, windowID: selection.windowID)
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
        guard let appState, let anchor = itemActionsAnchor, let item = selectedItem else {
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
        guard let appState, let item = selectedItem else {
            return
        }
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState)
        guard destinations.indices.contains(index), let section = destinations[index] else {
            return
        }
        MenuBarSearchItemActions.move(item, to: section, appState: appState, recordsUndo: true)
    }

    // MARK: Rename

    func beginRenamingSelection() {
        guard let selection = model.selection, let item = cachedItem(for: selection) else {
            return
        }
        model.renameSession = .init(tag: selection.tag, windowID: selection.windowID, draft: item.customName ?? "")
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
        // The results rank by names captured with their inventory; rebuild it.
        model.candidates = []
        if let appState {
            model.refresh(from: DisplayedItemInventory.cache(appState: appState), sections: appState.searchSections)
        }
    }

    // MARK: Opening an item

    /// Closes the panel first: a key panel over the menu bar would swallow the
    /// item's own menu.
    func activate(_ item: MenuBarItem) {
        guard model.renameSession?.targets(item) != true, let appState, let displayID else {
            return
        }
        close()
        model.recents.record(item)
        Task {
            await waitUntilClosed(timeout: .milliseconds(200))
            await appState.itemManager.activate(item: item, on: displayID)
        }
    }

    // MARK: Presentation

    /// Presents the panel, defaulting to the screen under the pointer.
    func show(on screen: NSScreen? = nil) {
        guard let appState else {
            return
        }
        guard let screen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main else {
            Self.diagLog.error("Missing screen for the search panel")
            return
        }
        presentation = appState.settings.visibility.menuBarSearchPresentation
        displayID = screen.displayID

        if !keepsQuery {
            model.searchText = ""
        }
        appState.navigationState.isSearchPresented = true

        // Reuse the hosting view, since a new SwiftUI graph per show
        // accumulates (see ThawBarHostingView.update).
        let rootView = MenuBarSearchRootView(appState: appState, model: model, panel: self, presentation: presentation)
        if let existing = contentView as? MenuBarSearchHostingView {
            existing.rootView = rootView
        } else {
            contentView = MenuBarSearchHostingView(rootView: rootView)
        }
        setFrame(frame(isCollapsed: presentation.isCollapsed(query: model.searchText), on: screen), display: false)
        makeKeyAndOrderFront(nil)

        outsideClickMonitor.start()
        shortcutMonitor.start()

        // Off the opening path, so the panel shows at once and rows fill in.
        pictureRefresh?.cancel()
        pictureRefresh = Task { [weak appState] in
            guard let appState else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.recaptureIfWarranted()
        }
    }

    /// Reads the highlighted row to VoiceOver after a key moved it.
    func announceSelection() {
        guard NSWorkspace.shared.isVoiceOverEnabled, let result = model.selectedResult else {
            return
        }
        AccessibilityAnnouncements.post(MenuBarSearchAnnouncement.row(result))
    }

    /// Resizes the window for the panel collapsing to its field or opening,
    /// keeping the field where it is.
    func fitFrame(isCollapsed: Bool) {
        guard let screen else {
            return
        }
        setFrame(frame(isCollapsed: isCollapsed, on: screen), display: true)
    }

    private func frame(isCollapsed: Bool, on screen: NSScreen) -> CGRect {
        SearchPanelGeometry.frame(isCollapsed: isCollapsed, in: screen.visibleFrame)
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    override func close() {
        pictureRefresh?.cancel()
        pictureRefresh = nil
        if !keepsQuery {
            model.searchText = ""
        }
        model.renameSession = nil
        super.close()
        // Hosting view retained deliberately; show() repoints it.
        outsideClickMonitor.stop()
        shortcutMonitor.stop()
        appState?.navigationState.isSearchPresented = false
        MemoryReclaimer.scheduleRelief(reason: "search panel closed")
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
}

extension AppState {
    /// The sections search groups items under: every one that is turned on.
    var searchSections: [MenuBarSection.Name] {
        MenuBarSection.Name.allCases.filter { menuBarManager.section(withName: $0)?.isEnabled ?? true }
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
