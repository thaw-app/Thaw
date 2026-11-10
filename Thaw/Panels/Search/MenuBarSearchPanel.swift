//
//  MenuBarSearchPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Combine
import Darwin
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
    static nonisolated let diagLog = DiagLog(category: "MenuBarSearchPanel")

    /// Must match the glass effect the hosted view draws.
    static let cornerRadius: CGFloat = ThawRadius.panel

    /// Grace delay after close before tearing down the hosted SwiftUI view hierarchy and search model lists.
    static let idleTeardownDelay: Duration = .seconds(2)

    /// Written only by adopt(_:), so a preference flipped while the panel is
    /// up cannot make close() save the wrong face's frame.
    private(set) var presentation: SearchPresentation = .inspector

    weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// A click right after a move is that move's tail, not a dismissal.
    private var moveActivity: MoveOperationTracker?

    var cacheTask: Task<Void, Never>?

    private var idleTeardownTask: Task<Void, Never>?

    /// Retargets the real menu bar spotlight to the highlighted row.
    var selectionObservationTask: Task<Void, Never>?

    /// Lights the selected item after a short delay; replaced on each
    /// selection change.
    var spotlightTask: Task<Void, Never>?

    /// Whether the agent confirmed the highlight, so teardown releases only
    /// a spotlight that landed.
    var isSpotlighted = false

    /// Captured up front so endSpotlight() releases the right item after the
    /// selection has moved on.
    var spotlightedName: String?

    let model = MenuBarSearchModel()
    var displayInvalidations: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()

    /// The actions button the actions menu hangs from. Weak because the
    /// hosting view owns it.
    weak var itemActionsAnchor: NSView?

    /// While the actions menu tracks, outside clicks and losing key must not
    /// dismiss the panel from under it.
    var isPresentingItemActions = false

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
        if keyCode == .e {
            beginRenamingSelection()
            return nil
        }
        // With no highlighted row these keys pass through.
        guard
            model.renameSession == nil, let appState, selectedItem != nil
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
    var isSamplingMenuBarColor = false

    /// Guards close() against re-entry when super.close() triggers didResignKeyNotification.
    private var isClosing = false

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: SearchPresentation.inspector.contentSize),
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
        idleTeardownTask?.cancel()
        endSpotlight()
    }

    @objc private func panelResignedKey(_: Notification) {
        // The actions menu takes focus; menuDidClose(_:) re-tests key afterwards.
        guard !isPresentingItemActions, isVisible else {
            return
        }
        close()
    }

    func performSetup(with appState: AppState, displayInvalidations: some Publisher<Void, Never>) {
        self.appState = appState
        self.displayInvalidations = displayInvalidations.eraseToAnyPublisher()
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

        // A display change closes at the posting, while the frame still belongs to its display.
        DisplayEnvironment.spaceOrDisplayChanges(merging: displayInvalidations)
            .sink { [weak self] in
                guard let self, isVisible || self.appState?.navigationState.isSearchPresented == true else { return }
                close()
            }
            .store(in: &cancellables)

        // The mode is unknown until the first showing, so this runs in every
        // mode and retargetSpotlight() declines where it does not apply.
        observeSelectionForSpotlight()
    }

    // MARK: Presentation

    /// Presents the panel, defaulting to the screen under the pointer.
    func show(on screen: NSScreen? = nil) {
        guard let appState else {
            return
        }
        idleTeardownTask?.cancel()
        idleTeardownTask = nil
        appState.imageCache.loadFromDiskIfNeeded()
        guard let screen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main else {
            Self.diagLog.error("Missing screen for \(presentation.logLabel)")
            return
        }

        let modeChanged = adopt(appState.settings.advanced.menuBarSearchPresentation)

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

        warmCachesOnShow(appState: appState)
    }

    /// The one place the mode is adopted, from show(on:); true when it changed.
    func adopt(_ mode: SearchPresentation) -> Bool {
        let changed = mode != presentation
        presentation = mode
        updateMenuBarColorSampling()
        return changed
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        let hasHostedContent = isVisible || contentView is MenuBarSearchHostingView || contentViewController != nil || isSamplingMenuBarColor
        if presentation.persistsFrame, isVisible, let screen, contentView != nil {
            saveFrameForDisplay(screen)
        }
        cacheTask?.cancel()
        cacheTask = nil
        model.focusTask?.cancel()
        endSpotlight()
        if !keepsQuery {
            model.searchText = ""
        }
        model.renameSession = nil
        makeFirstResponder(nil)
        orderOut(nil)
        super.close()
        outsideClickMonitor.stop()
        shortcutMonitor.stop()
        appState?.navigationState.isSearchPresented = false
        if hasHostedContent {
            scheduleIdleTeardown()
            MemoryReclaimer.scheduleRelief(reason: "\(presentation.logLabel) closed")
        }
    }

    private func scheduleIdleTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.idleTeardownDelay)
            } catch {
                return
            }
            self?.tearDownForIdle()
        }
    }

    /// Drops the SwiftUI hosting hierarchy and search model caches after the panel stays closed past grace.
    func tearDownForIdle() {
        idleTeardownTask?.cancel()
        idleTeardownTask = nil
        guard !isVisible else { return }
        AppState.tearDownWindowHierarchy(self, clearDelegate: false)
        model.displayedItems = []
        model.launcherCandidates = []
        model.selection = nil
        model.detach()
        isSamplingMenuBarColor = false
        MemoryReclaimer.scheduleRelief(reason: "\(presentation.logLabel) idle teardown")
        _ = malloc_zone_pressure_relief(nil, 0)
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
