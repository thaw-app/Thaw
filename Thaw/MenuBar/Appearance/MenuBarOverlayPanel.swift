//
//  MenuBarOverlayPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import ScreenCaptureKit

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
final class MenuBarOverlayPanel: NSPanel, @unchecked Sendable {
    private let diagLog = DiagLog(category: "MenuBarOverlayPanel")
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame

        var description: String {
            rawValue
        }
    }

    /// The kind of validation that occurs before an update.
    private enum ValidationKind {
        case showing
        case updates
    }

    /// A context that manages panel update tasks.
    private final class UpdateTaskContext {
        private var tasks = [UpdateFlag: Task<Void, any Error>]()

        /// Sets the task for the given update flag.
        ///
        /// Setting the task cancels the previous task for the flag, if there is one.
        ///
        /// - Parameters:
        ///   - flag: The update flag to set the task for.
        ///   - timeout: The timeout of the task.
        ///   - operation: The operation for the task to perform.
        func setTask(
            for flag: UpdateFlag,
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> Void
        ) {
            cancelTask(for: flag)
            tasks[flag] = Self.runWithTimeout(timeout: timeout, operation: operation)
        }

        private static func runWithTimeout(
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> Void
        ) -> Task<Void, Error> {
            Task {
                try await operation()
                try? await Task.sleep(for: timeout)
            }
        }

        /// Cancels the task for the given update flag.
        ///
        /// - Parameter flag: The update flag to cancel the task for.
        func cancelTask(for flag: UpdateFlag) {
            tasks.removeValue(forKey: flag)?.cancel()
        }

        /// Cancels all tasks.
        func cancelAllTasks() {
            for task in tasks.values {
                task.cancel()
            }
            tasks.removeAll()
        }
    }

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// A Boolean value that indicates whether Mission Control or App Expose is active.
    @Published private var isMissionControlActive = false

    /// Flags representing the components of the panel currently in need of an update.
    @Published private(set) var updateFlags = Set<UpdateFlag>()

    /// The frame of the application menu.
    @Published private(set) var applicationMenuFrame: CGRect?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// Retry task for show() when it fails due to unsettled Window Server.
    private var showRetryTask: Task<Void, Never>?

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A tiny invisible window used to detect Mission Control.
    ///
    /// This window is NOT stationary, so it moves during Mission Control.
    /// By comparing its actual on-screen position with its intended position,
    /// we can reliably detect if Mission Control is active.
    private lazy var missionControlProbeWindow: NSPanel = {
        let window = NSPanel(
            contentRect: CGRect(x: owningScreen.frame.midX, y: owningScreen.frame.midY, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.alphaValue = 0.0
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        // Specifically NOT .stationary or .transient to allow movement.
        // .ignoresCycle and .fullScreenAuxiliary help hide the 'Thaw' label.
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        // Low enough for Mission Control to arrange (both axes move).
        // Positioned at screen center so MC grid displaces it in both x and y.
        window.level = .floating
        return window
    }()

    /// The origin of the probe window when it is at rest (not in Mission Control).
    private var probeAtRestOrigin: CGPoint?

    /// The time when the probe window first became displaced.
    private var missionControlDisplacedSince: Date?

    /// Creates an overlay panel with the given app state and owning screen.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless, .fullSizeContentView, .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.title = String(localized: "Menu Bar Overlay")
        self.backgroundColor = .clear
        self.hasShadow = false
        self.animationBehavior = .none
        self.hidesOnDeactivate = false
        self.canHide = false
        self.isMovable = false
        self.ignoresMouseEvents = true
        self.isExcludedFromWindowsMenu = true
        self.collectionBehavior = [
            .fullScreenNone, .ignoresCycle, .stationary,
        ]
        self.contentView = MenuBarOverlayPanelContentView()
        configureCancellables()

        missionControlProbeWindow.orderFrontRegardless()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Show the panel on the active space.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isMissionControlActive = false
                self?.needsShow = true
            }
            .store(in: &c)

        // Poll the mission control probe window to detect if it has moved/scaled.
        Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let windowID = CGWindowID(self.missionControlProbeWindow.windowNumber)
                if let actualBounds = Bridging.getWindowBounds(for: windowID) {
                    let actualOrigin = actualBounds.origin

                    // Capture the "at-rest" origin when we're reasonably sure we're not in Mission Control
                    if self.probeAtRestOrigin == nil {
                        self.probeAtRestOrigin = actualOrigin
                        return
                    }

                    guard let atRest = self.probeAtRestOrigin else { return }

                    let isActive = abs(actualOrigin.x - atRest.x) > 1.0 &&
                        abs(actualOrigin.y - atRest.y) > 1.0

                    let now = Date()

                    if isActive {
                        if let displacedSince = self.missionControlDisplacedSince {
                            if now.timeIntervalSince(displacedSince) > 0.1 {
                                self.isMissionControlActive = true
                            }
                        } else {
                            self.missionControlDisplacedSince = now
                        }
                    } else {
                        self.missionControlDisplacedSince = nil
                        self.isMissionControlActive = false
                    }
                }
            }
            .store(in: &c)

        // Update application menu frame when the menu bar owning or frontmost app changes.
        Publishers.Merge(
            NSWorkspace.shared.publisher(
                for: \.menuBarOwningApplication,
                options: .old
            )
            .combineLatest(
                NSWorkspace.shared.publisher(
                    for: \.menuBarOwningApplication,
                    options: .new
                )
            )
            .compactMap { $0 == $1 ? nil : $0 },
            NSWorkspace.shared.publisher(
                for: \.frontmostApplication,
                options: .old
            )
            .combineLatest(
                NSWorkspace.shared.publisher(
                    for: \.frontmostApplication,
                    options: .new
                )
            )
            .compactMap { $0 == $1 ? nil : $0 }
        )
        .removeDuplicates()
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            updateTaskContext.setTask(
                for: .applicationMenuFrame,
                timeout: .seconds(10)
            ) { @MainActor [weak self] in
                var candidate: CGRect?
                var settledCount = 0
                for i in 0 ..< 10 {
                    do {
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    guard let self else { return }
                    let latest = self.owningScreen
                        .getApplicationMenuFrame(bypassCache: true)
                    guard let latest else { continue }
                    let isFirst = i == 0
                    var changed = true
                    if let c = candidate {
                        changed = latest != c
                    }
                    if isFirst || changed {
                        self.applicationMenuFrame = latest
                        candidate = latest
                        settledCount = 0
                    } else {
                        settledCount += 1
                        if settledCount >= 3 {
                            return
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                if self.owningScreen != NSScreen.main {
                    self.updateTaskContext.cancelTask(
                        for: .applicationMenuFrame
                    )
                }
            }
        }
        .store(in: &c)

        // Special cases for when the user drags an app onto or clicks into another space.
        Publishers.Merge(
            publisher(for: \.isOnActiveSpace)
                .receive(on: DispatchQueue.main)
                .replace(with: ()),
            EventMonitor.publish(events: .leftMouseUp, scope: .universal)
                .filter { [weak self] _ in self?.isOnActiveSpace ?? false }
                .replace(with: ())
        )
        .debounce(for: 0.05, scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.insertUpdateFlag(.applicationMenuFrame)
        }
        .store(in: &c)

        Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isOnActiveSpace else {
                    return
                }
                self.insertUpdateFlag(.applicationMenuFrame)
            }
            .store(in: &c)

        $needsShow
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] needsShow in
                guard let self, needsShow else {
                    return
                }
                defer {
                    self.needsShow = false
                }
                show()
            }
            .store(in: &c)

        $updateFlags
            .sink { [weak self] flags in
                guard let self, !flags.isEmpty else {
                    return
                }
                Task {
                    // Must be run async, or this will not remove the flags.
                    self.updateFlags.removeAll()
                }
                let windows = WindowInfo.createWindows(option: .onScreen)
                if validate(for: .updates, with: windows) {
                    performUpdates(
                        for: flags,
                        windows: windows,
                        screen: owningScreen
                    )
                }
            }
            .store(in: &c)

        if let appState {
            Publishers.CombineLatest(
                appState.menuBarManager.$isMenuBarHiddenBySystem,
                $isMissionControlActive
            )
            .sink { [weak self] isMenuBarHidden, isMissionControlActive in
                let isHidden = isMenuBarHidden || isMissionControlActive
                self?.alphaValue = isHidden ? 0 : 1
            }
            .store(in: &c)

            appState.appearanceManager.$configuration
                .sink { [weak self] _ in
                    self?.updateWindowLevel()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Performs validation for the given validation kind. Returns the panel's
    /// owning display if successful. Returns `nil` on failure.
    private func validate(for kind: ValidationKind, with windows: [WindowInfo])
        -> Bool
    {
        lazy var actionMessage =
            switch kind {
            case .showing: "Preventing overlay panel from showing."
            case .updates: "Preventing overlay panel from updating."
            }
        guard let appState else {
            diagLog.debug("No app state. \(actionMessage)")
            return false
        }
        guard
            appState.menuBarManager.hasValidMenuBar(
                in: windows,
                for: owningScreen.displayID
            )
        else {
            diagLog.debug("No valid menu bar found. \(actionMessage)")
            return false
        }
        return true
    }

    /// Stores the frame of the menu bar's application menu.
    private func updateApplicationMenuFrame(for screen: NSScreen) {
        guard
            let menuBarManager = appState?.menuBarManager,
            !menuBarManager.isMenuBarHiddenBySystem
        else {
            return
        }
        applicationMenuFrame = screen.getApplicationMenuFrame()
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(
        for flags: Set<UpdateFlag>,
        windows _: [WindowInfo],
        screen: NSScreen
    ) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: screen)
        }
    }

    /// Shows the panel.
    private func show() {
        guard let appState else {
            return
        }

        guard appState.appearanceManager.overlayPanels.contains(self) else {
            diagLog.warning("Overlay panel \(self) not retained")
            return
        }

        // Validate before showing to ensure panel should be visible on this screen.
        let windows = WindowInfo.createWindows(option: .onScreen)
        guard validate(for: .showing, with: windows) else {
            scheduleShowRetry()
            return
        }

        guard let menuBarHeight = owningScreen.getMenuBarHeight() else {
            scheduleShowRetry()
            return
        }

        showRetryTask?.cancel()
        showRetryTask = nil

        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )

        updateWindowLevel()
        alphaValue = 0
        setFrame(newFrame, display: true)
        orderFrontRegardless()

        updateFlags = [.applicationMenuFrame]

        if !appState.menuBarManager.isMenuBarHiddenBySystem {
            alphaValue = 1
        }
    }

    /// Schedules a retry of show() after a delay when validation or
    /// menu bar height was not available (e.g. during a display change
    /// before the Window Server has settled). Only the latest retry
    /// is kept; cancelled if show() succeeds in the meantime.
    private func scheduleShowRetry() {
        showRetryTask?.cancel()
        showRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.needsShow = true }
        }
    }

    /// Workaround to release owningScreen reference since it's a let constant
    /// We can't change owningScreen to var because it's used throughout the panel,
    /// but we can clear other references to help with deallocation
    private func cleanupReferences() {
        // Clear all published state to release retained objects
        applicationMenuFrame = nil
        updateFlags.removeAll()
        probeAtRestOrigin = nil
    }

    override func close() {
        showRetryTask?.cancel()
        showRetryTask = nil
        // Cancel all pending update tasks to prevent memory leaks
        updateTaskContext.cancelAllTasks()
        // Clear publishers to release references
        cancellables.removeAll()
        // Clear captured wallpaper image and other state
        cleanupReferences()
        // Release content view
        contentView = nil
        // Close the mission control probe window
        missionControlProbeWindow.close()
        super.close()
        #if DEBUG
            diagLog.debug("Overlay panel closed. Active windows: \(NSApplication.shared.windows.count)")
        #endif
    }

    /// Moves the panel behind the menu bar whenever a tint or shape is active
    /// so the menu bar's own blur blends the content and items stay crisp.
    private func updateWindowLevel() {
        guard let appState else { return }
        let config = appState.appearanceManager.configuration
        if config.current.tintKind != .noTint || config.shapeKind != .noShape || config.current.backgroundKind != .none {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
        } else {
            level = .statusBar
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

private final class MenuBarOverlayPanelContentView: NSView {
    @Published private var fullConfiguration: MenuBarAppearanceConfigurationV2 =
        .defaultConfiguration

    @Published private var previewConfiguration:
        MenuBarAppearancePartialConfiguration?

    @Published private var averageColorInfo: MenuBarAverageColorInfo?

    private var cancellables = Set<AnyCancellable>()

    private lazy var tintGlassView: NSGlassEffectView = {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        view.contentView = content
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }()

    private lazy var tintGlassMaskLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        return layer
    }()

    private lazy var tintGlassContentMaskLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        return layer
    }()

    private lazy var tintGlassBorderLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        return layer
    }()

    private var shapeCGPath: CGPath?

    /// Cached menu bar item windows, updated by publishers instead of
    /// being queried synchronously during each `draw(_:)` call.
    private var cachedItemWindows: [WindowInfo] = []

    /// In-flight confirmation task for settling the trailing item-window cache
    /// after an app switch. Cancelled and replaced whenever a new
    /// applicationMenuFrame value arrives so that only the latest app's icon
    /// layout is committed.
    private var itemWindowsConfirmTask: Task<Void, Never>?

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The currently displayed configuration.
    private var configuration: MenuBarAppearancePartialConfiguration {
        if let appState = overlayPanel?.appState,
           let preview = appState.appearanceManager.previewConfiguration
        {
            return preview
        }
        return fullConfiguration.current
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let overlayPanel {
            if let appState = overlayPanel.appState {
                appState.appearanceManager.$configuration
                    .sink { [weak self] config in
                        self?.fullConfiguration = config
                    }
                    .store(in: &c)

                appState.appearanceManager.objectWillChange
                    .debounce(for: .seconds(0), scheduler: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else { return }
                        fullConfiguration = appState.appearanceManager.configuration
                    }
                    .store(in: &c)

                appState.appearanceManager.$previewConfiguration
                    .removeDuplicates()
                    .assign(to: &$previewConfiguration)

                appState.menuBarManager.$averageColors
                    .sink { [weak self] colors in
                        guard let self, let displayID = self.overlayPanel?.owningScreen.displayID else { return }
                        self.averageColorInfo = colors[displayID]
                    }
                    .store(in: &c)

                // Fade out whenever a menu bar item is being dragged.
                appState.$isDraggingMenuBarItem
                    .removeDuplicates()
                    .sink { [weak self] isDragging in
                        if isDragging {
                            self?.animator().alphaValue = 0
                        } else {
                            self?.animator().alphaValue = 1
                        }
                    }
                    .store(in: &c)

                for section in appState.menuBarManager.sections {
                    // Redraw whenever the window frame of a control item changes.
                    //
                    // - NOTE: A previous attempt was made to redraw the view when the
                    //   section's `isHidden` property was changed. This would be semantically
                    //   ideal, but the property sometimes changes before the menu bar items
                    //   are actually updated on-screen. Since the view's drawing process relies
                    //   on getting an accurate position of each menu bar item, we need to use
                    //   something that publishes its changes only after the items are updated.
                    section.controlItem.$onScreenFrame
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            self?.updateCachedItemWindows()
                            self?.needsDisplay = true
                        }
                        .store(in: &c)
                }
            }

            // Redraw whenever the application menu frame changes.
            // Also refresh cached item windows to pick up items added/removed
            // by other apps (e.g. status bar icons appearing or disappearing).
            //
            // The item windows are re-read with a two-read confirmation loop
            // (mirroring the AX confirmation used for applicationMenuFrame) so
            // that we never commit a transitional Window Server layout. The
            // trailing shape shadow artefact on app-switch was caused by
            // calling updateCachedItemWindows() synchronously here, before the
            // icon windows had settled into their new positions.
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    guard let self, let screen = self.overlayPanel?.owningScreen else { return }
                    self.scheduleItemWindowsConfirmation(for: screen)
                }
                .store(in: &c)
        }

        // Redraw whenever the configurations or average color change.
        $fullConfiguration.replace(with: ())
            .merge(with: $previewConfiguration.replace(with: ()))
            .merge(with: $averageColorInfo.replace(with: ()))
            .sink { [weak self] _ in
                self?.updateBackgroundGlass()
                self?.needsDisplay = true
            }
            .store(in: &c)

        cancellables = c

        // Populate the cache immediately so the first draw has data.
        updateCachedItemWindows()
    }

    /// Refreshes the cached menu bar item windows from the Window Server.
    ///
    /// Calling this directly (e.g. from the controlItem frame-change path)
    /// cancels any in-flight confirmation task so that a fresh synchronous read
    /// always wins over a stale async one.
    private func updateCachedItemWindows() {
        itemWindowsConfirmTask?.cancel()
        itemWindowsConfirmTask = nil
        guard let screen = overlayPanel?.owningScreen else {
            cachedItemWindows = []
            return
        }
        cachedItemWindows = MenuBarItem.getMenuBarItemWindows(
            on: screen.displayID,
            option: .onScreen
        )
    }

    /// Starts an async confirmation task that re-reads menu bar item windows
    /// until two consecutive reads return the same total width, then commits
    /// the result. This mirrors the two-read AX confirmation used for
    /// `applicationMenuFrame` and prevents the trailing shape from being drawn
    /// with a stale (transitional) icon layout immediately after an app switch.
    private func scheduleItemWindowsConfirmation(for screen: NSScreen) {
        // Hoist displayID before entering the Task so that no AppKit
        // (NSScreen) access occurs off the main thread.
        let displayID = screen.displayID
        itemWindowsConfirmTask?.cancel()
        itemWindowsConfirmTask = Task { [weak self] in
            guard let self else { return }
            var candidate: [WindowInfo]?
            var candidateWidth: CGFloat = 0
            var settledCount = 0
            for i in 0 ..< 10 {
                guard !Task.isCancelled else { return }
                let latest = MenuBarItem.getMenuBarItemWindows(
                    on: displayID,
                    option: .onScreen
                )
                let latestWidth = latest.reduce(0) { $0 + $1.bounds.width }

                if i == 0 || abs(latestWidth - candidateWidth) >= 1 {
                    // First read or width changed — commit immediately.
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.cachedItemWindows = latest
                        self.needsDisplay = true
                    }
                    candidate = latest
                    candidateWidth = latestWidth
                    settledCount = 0
                } else {
                    settledCount += 1
                    if settledCount >= 3 {
                        // Stable for 2 consecutive reads — done.
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // Exhausted retries — commit last value if not already settled.
            if let candidate {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.cachedItemWindows = candidate
                    self.needsDisplay = true
                }
            }
        }
    }

    /// Returns a path in the given rectangle, with the given end caps,
    /// and inset by the given amounts.
    private func shapePath(
        in rect: CGRect,
        leadingEndCap: MenuBarEndCap,
        trailingEndCap: MenuBarEndCap,
        screen: NSScreen
    ) -> NSBezierPath {
        let insetRect: CGRect =
            if !screen.hasNotch {
                switch (leadingEndCap, trailingEndCap) {
                case (.square, .square):
                    CGRect(
                        x: rect.origin.x,
                        y: rect.origin.y + 1,
                        width: rect.width,
                        height: rect.height - 2
                    )
                case (.square, .round):
                    CGRect(
                        x: rect.origin.x,
                        y: rect.origin.y + 1,
                        width: rect.width - 1,
                        height: rect.height - 2
                    )
                case (.round, .square):
                    CGRect(
                        x: rect.origin.x + 1,
                        y: rect.origin.y + 1,
                        width: rect.width - 1,
                        height: rect.height - 2
                    )
                case (.round, .round):
                    CGRect(
                        x: rect.origin.x + 1,
                        y: rect.origin.y + 1,
                        width: rect.width - 2,
                        height: rect.height - 2
                    )
                }
            } else {
                rect
            }

        let shapeBounds = CGRect(
            x: insetRect.minX + insetRect.height / 2,
            y: insetRect.minY,
            width: insetRect.width - insetRect.height,
            height: insetRect.height
        )
        let leadingEndCapBounds = CGRect(
            x: insetRect.minX,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )
        let trailingEndCapBounds = CGRect(
            x: insetRect.maxX - insetRect.height,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )

        var path = NSBezierPath(rect: shapeBounds)

        path =
            switch leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

        path =
            switch trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/notch`` shape kind.
    /// Behaves like full on non-notched displays, splits at the notch
    /// on notched displays.
    private func pathForNotchShape(
        in rect: CGRect,
        info: MenuBarNotchShapeInfo,
        isInset: Bool,
        screen: NSScreen
    ) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager
        else {
            return NSBezierPath()
        }

        // Non-notched: behaves like full shape using the outer end caps
        guard screen.hasNotch,
              let topLeft = screen.auxiliaryTopLeftArea,
              let topRight = screen.auxiliaryTopRightArea
        else {
            let fullInfo = MenuBarFullShapeInfo(
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            return pathForFullShape(in: rect, info: fullInfo, isInset: isInset, screen: screen)
        }

        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }

        let screenOrigin = screen.frame.minX

        let notchMargin = fullConfiguration.notchMargin

        let leadingBounds: CGRect = {
            let notchLeftX = topLeft.maxX - screenOrigin - notchMargin
            let adjustedMinX = rect.minX + fullConfiguration.leftMargin
            let width = max(0, notchLeftX - adjustedMinX)
            return CGRect(x: adjustedMinX, y: rect.minY, width: width, height: rect.height)
        }()

        let trailingBounds: CGRect = {
            let notchRightX = topRight.minX - screenOrigin + notchMargin
            let maxX = rect.maxX - fullConfiguration.rightMargin
            let width = max(0, maxX - notchRightX)
            return CGRect(x: notchRightX, y: rect.minY, width: width, height: rect.height)
        }()

        if leadingBounds.width <= 0 || trailingBounds.width <= 0
            || leadingBounds.intersects(trailingBounds)
        {
            let fullInfo = MenuBarFullShapeInfo(
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            return pathForFullShape(in: rect, info: fullInfo, isInset: isInset, screen: screen)
        }

        let leadingPath = shapePath(
            in: leadingBounds,
            leadingEndCap: info.leading.leadingEndCap,
            trailingEndCap: info.leading.trailingEndCap,
            screen: screen
        )

        let trailingPath = shapePath(
            in: trailingBounds,
            leadingEndCap: info.trailing.leadingEndCap,
            trailingEndCap: info.trailing.trailingEndCap,
            screen: screen
        )

        let path = NSBezierPath()
        path.append(leadingPath)
        path.append(trailingPath)
        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShape(
        in rect: CGRect,
        info: MenuBarFullShapeInfo,
        isInset: Bool,
        screen: NSScreen
    ) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager
        else {
            return NSBezierPath()
        }
        var rect = rect
        rect.origin.x += fullConfiguration.leftMargin
        rect.size.width -= (fullConfiguration.leftMargin + fullConfiguration.rightMargin)

        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        return shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap,
            screen: screen
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(
        in rect: CGRect,
        info: MenuBarSplitShapeInfo,
        isInset: Bool,
        screen: NSScreen
    ) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager
        else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }

        let leadingPathBounds: CGRect = {
            guard
                let applicationMenuFrame = overlayPanel?.applicationMenuFrame,
                applicationMenuFrame.width > 0
            else {
                return .zero
            }
            // Calculate offset to account for menu position relative to rect origin
            let offset = applicationMenuFrame.origin.x - rect.minX
            var maxX = applicationMenuFrame.maxX
            if shouldInset {
                maxX += 10
                if info.leading.leadingEndCap == .square {
                    maxX += appearanceManager.menuBarInsetAmount
                }
            } else {
                maxX += 20
            }
            return CGRect(
                x: rect.minX + fullConfiguration.leftMargin,
                y: rect.minY,
                width: max(0, maxX - offset - fullConfiguration.leftMargin),
                height: rect.height
            )
        }()
        let trailingPathBounds: CGRect = {
            let itemWindows = cachedItemWindows
            guard !itemWindows.isEmpty else {
                return .zero
            }
            // Filter to only include items on this display
            let screenFrame = screen.frame
            let displayItemWindows = itemWindows.filter { item in
                item.bounds.midX >= screenFrame.minX && item.bounds.midX <= screenFrame.maxX
            }
            // If no items on this display, don't show trailing shape
            guard !displayItemWindows.isEmpty else {
                return .zero
            }
            let totalWidth = displayItemWindows.reduce(into: 0) { width, item in
                width += item.bounds.width
            }
            var position = rect.maxX - totalWidth
            if shouldInset {
                position += 4
                if info.trailing.trailingEndCap == .square {
                    position -= appearanceManager.menuBarInsetAmount
                }
            } else {
                position -= 7
            }
            return CGRect(
                x: position,
                y: rect.minY,
                width: max(0, (rect.maxX - fullConfiguration.rightMargin) - position),
                height: rect.height
            )
        }()

        if leadingPathBounds == .zero || trailingPathBounds == .zero
            || leadingPathBounds.intersects(trailingPathBounds)
        {
            var fallbackRect = rect
            fallbackRect.origin.x += fullConfiguration.leftMargin
            fallbackRect.size.width -= (fullConfiguration.leftMargin + fullConfiguration.rightMargin)
            return shapePath(
                in: fallbackRect,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
        } else {
            let leadingPath = shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap,
                screen: screen
            )
            let trailingPath = shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
            let path = NSBezierPath()
            path.append(leadingPath)
            path.append(trailingPath)
            return path
        }
    }

    /// Returns the bounds that the view's drawn content can occupy.
    private func getDrawableBounds() -> CGRect {
        return CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )
    }

    /// Draws the tint defined by the given configuration in the given rectangle.
    private func drawTint(in rect: CGRect) {
        switch configuration.tintKind {
        case .noTint, .glass:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: configuration.tintColor)?
                .withAlphaComponent(configuration.tintOpacity)
            {
                tintColor.setFill()
                rect.fill()
            }
        case .gradient:
            if let tintGradient = configuration.tintGradient
                .withAlpha(configuration.tintOpacity)
                .nsGradient(using: .displayP3)
            {
                tintGradient.draw(in: rect, angle: 0)
            }
        case .adaptive:
            if let colorInfo = averageColorInfo,
               let color = NSColor(cgColor: colorInfo.color)?
               .withAlphaComponent(configuration.tintOpacity)
            {
                color.setFill()
                rect.fill()
            }
        }
    }

    private var isBackgroundGlassActive = false

    /// Adds or removes the glass container on the panel based on background kind.
    private func updateBackgroundGlass() {
        guard let panel = window as? MenuBarOverlayPanel else { return }
        if configuration.backgroundKind == .glass {
            if isBackgroundGlassActive {
                if let glassView = panel.contentView?.subviews
                    .compactMap({ $0 as? NSGlassEffectView }).first
                {
                    glassView.style = configuration.backgroundGlassStyle.nsGlassStyle
                }
                return
            }
            guard let realContent = panel.contentView else { return }
            isBackgroundGlassActive = true

            let container = NSView()
            container.wantsLayer = true

            let glassView = NSGlassEffectView()
            glassView.style = configuration.backgroundGlassStyle.nsGlassStyle
            glassView.cornerRadius = 0
            glassView.translatesAutoresizingMaskIntoConstraints = false

            realContent.removeFromSuperview()
            realContent.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(glassView, positioned: .below, relativeTo: nil)
            container.addSubview(realContent, positioned: .above, relativeTo: nil)
            panel.contentView = container

            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: container.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),

                realContent.topAnchor.constraint(equalTo: container.topAnchor),
                realContent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                realContent.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                realContent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        } else if isBackgroundGlassActive {
            isBackgroundGlassActive = false
            guard let container = panel.contentView,
                  let realContent = container.subviews
                  .compactMap({ $0 as? MenuBarOverlayPanelContentView }).first
            else { return }
            realContent.removeFromSuperview()
            panel.contentView = realContent
        }
    }

    /// Adds or removes the tint glass effect subview, masked to the shape path.
    private func updateTintGlass() {
        if configuration.tintKind == .glass, let shapeCGPath {
            if tintGlassView.superview == nil {
                addSubview(tintGlassView, positioned: .above, relativeTo: nil)
                NSLayoutConstraint.activate([
                    tintGlassView.topAnchor.constraint(equalTo: topAnchor),
                    tintGlassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    tintGlassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    tintGlassView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
                tintGlassView.layer?.mask = tintGlassMaskLayer
                tintGlassView.contentView?.layer?.mask = tintGlassContentMaskLayer
                tintGlassView.contentView?.layer?.addSublayer(tintGlassBorderLayer)
            }
            tintGlassMaskLayer.path = shapeCGPath
            tintGlassContentMaskLayer.path = shapeCGPath
            tintGlassView.style = configuration.tintGlassStyle.nsGlassStyle

            if configuration.hasBorder {
                tintGlassBorderLayer.path = shapeCGPath
                tintGlassBorderLayer.strokeColor = configuration.borderColor
                tintGlassBorderLayer.lineWidth = configuration.borderWidth * 2
                tintGlassBorderLayer.isHidden = false
            } else {
                tintGlassBorderLayer.isHidden = true
            }

            tintGlassView.isHidden = false
        } else if tintGlassView.superview != nil {
            tintGlassView.isHidden = true
            tintGlassBorderLayer.isHidden = true
        }
    }

    /// Draws the background surrounding the shape in the given rectangle.
    private func drawBackground(in rect: CGRect) {
        switch configuration.backgroundKind {
        case .none:
            break
        case .solid:
            if let color = NSColor(cgColor: configuration.backgroundColor)?
                .withAlphaComponent(configuration.backgroundOpacity)
            {
                color.setFill()
                rect.fill()
            }
        case .gradient:
            if let gradient = configuration.backgroundGradient
                .withAlpha(configuration.backgroundOpacity)
                .nsGradient(using: .displayP3)
            {
                gradient.draw(in: rect, angle: 0)
            }
        case .glass:
            break
        case .adaptive:
            if let colorInfo = averageColorInfo,
               let color = NSColor(cgColor: colorInfo.color)?
               .withAlphaComponent(configuration.backgroundOpacity)
            {
                color.setFill()
                rect.fill()
            }
        }
    }

    /// Draws the background shadow at the top edge of the given rectangle.
    private func drawBackgroundShadow(in rect: CGRect) {
        guard configuration.backgroundHasShadow else { return }
        guard let gradient = NSGradient(
            colors: [
                NSColor(white: 0.0, alpha: 0.0),
                NSColor(white: 0.0, alpha: 0.2),
            ]
        ) else { return }
        let shadowBounds = CGRect(
            x: rect.minX,
            y: rect.minY - 5,
            width: rect.width,
            height: 5
        )
        gradient.draw(in: shadowBounds, angle: 90)
    }

    /// Draws the background border at the top edge of the given rectangle.
    private func drawBackgroundBorder(in rect: CGRect) {
        guard configuration.backgroundHasBorder else { return }
        guard let color = NSColor(cgColor: configuration.backgroundBorderColor) else { return }
        let borderBounds = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: configuration.backgroundBorderWidth
        )
        color.setFill()
        NSBezierPath(rect: borderBounds).fill()
    }

    override func draw(_: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let drawableBounds = getDrawableBounds()

        let shapePath =
            switch fullConfiguration.shapeKind {
            case .noShape:
                NSBezierPath(rect: drawableBounds)
            case .full:
                pathForFullShape(
                    in: drawableBounds,
                    info: fullConfiguration.fullShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            case .split:
                pathForSplitShape(
                    in: drawableBounds,
                    info: fullConfiguration.splitShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            case .notch:
                pathForNotchShape(
                    in: drawableBounds,
                    info: fullConfiguration.notchShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            }

        shapeCGPath = shapePath.cgPath
        updateTintGlass()

        var hasBorder = false

        // Background always draws first (full area, behind shapes)
        drawBackground(in: drawableBounds)
        drawBackgroundShadow(in: drawableBounds)
        drawBackgroundBorder(in: drawableBounds)

        switch fullConfiguration.shapeKind {
        case .noShape:
            // No shape tint/shadow/border — background only
            break
        case .full, .split, .notch:
            if configuration.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(
                    color: .black.withAlphaComponent(0.5),
                    radius: 5
                )
            }

            if configuration.hasBorder, configuration.tintKind != .glass {
                hasBorder = true
            }

            do {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                shapePath.setClip()

                drawTint(in: drawableBounds)
            }

            if hasBorder,
               let borderColor = NSColor(cgColor: configuration.borderColor)
            {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let borderPath = shapePath

                borderPath.lineWidth = configuration.borderWidth * 2
                borderPath.setClip()

                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}
