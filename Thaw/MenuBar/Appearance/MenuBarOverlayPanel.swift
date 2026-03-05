//
//  MenuBarOverlayPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
final class MenuBarOverlayPanel: NSPanel {
    private let diagLog = DiagLog(category: "MenuBarOverlayPanel")
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame
        case desktopWallpaper

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
            operation: @escaping () async throws -> Void
        ) {
            cancelTask(for: flag)
            tasks[flag] = Task.detached {
                try await Self.runWithTimeout(timeout, operation: operation)
            }
        }

        /// Runs an operation with a timeout, cancelling it if the timeout elapses.
        private static func runWithTimeout(
            _ timeout: Duration,
            operation: @escaping () async throws -> Void
        ) async throws {
            let operationTask = Task {
                try await operation()
            }
            let timeoutTask = Task {
                try await Task.sleep(for: timeout)
                operationTask.cancel()
                throw CancellationError()
            }

            do {
                try await operationTask.value
                timeoutTask.cancel()
            } catch {
                timeoutTask.cancel()
                operationTask.cancel()
                throw error
            }
        }

        /// Cancels the task for the given update flag.
        ///
        /// - Parameter flag: The update flag to cancel the task for.
        func cancelTask(for flag: UpdateFlag) {
            tasks.removeValue(forKey: flag)?.cancel()
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

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    ///
    /// The wallpaper is captured at nominal resolution (1x) to save memory.
    @Published private(set) var desktopWallpaper: CGImage?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

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
            contentRect: CGRect(x: owningScreen.frame.minX, y: owningScreen.frame.minY, width: 1, height: 1),
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
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        // High level often bypasses labeling in Mission Control.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow) - 1))
        return window
    }()

    /// The origin of the probe window when it is at rest (not in Mission Control).
    private var probeAtRestOrigin: CGPoint?

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
        self.level = appState.appearanceManager.configuration.showsMenuBarBackground
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
            : .statusBar
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
            .fullScreenNone, .ignoresCycle, .moveToActiveSpace, .stationary,
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

                    let isActive = abs(actualOrigin.x - atRest.x) > 1.0 ||
                        abs(actualOrigin.y - atRest.y) > 1.0

                    if isActive != self.isMissionControlActive {
                        self.isMissionControlActive = isActive
                    }
                }
            }
            .store(in: &c)

        // Update when light/dark mode changes.
        DistributedNotificationCenter.default()
            .publisher(
                for: DistributedNotificationCenter
                    .interfaceThemeChangedNotification
            )
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                updateTaskContext.setTask(
                    for: .desktopWallpaper,
                    timeout: .seconds(5)
                ) { [weak self] in
                    self?.insertUpdateFlag(.desktopWallpaper)
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
            ) { [weak self] in
                for _ in 0 ..< 10 {
                    try Task.checkCancellation()
                    guard let self else { return }
                    if let latestFrame = self.owningScreen
                        .getApplicationMenuFrame(),
                        latestFrame != self.applicationMenuFrame
                    {
                        self.insertUpdateFlag(.applicationMenuFrame)
                        break
                    }
                    try await Task.sleep(for: .milliseconds(100))
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

        // Continually update the desktop wallpaper. Ideally, we would set up an observer
        // for a wallpaper change notification, but macOS doesn't post one anymore.
        Timer.publish(every: 120, tolerance: 15, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isOnActiveSpace else {
                    return
                }
                self.insertUpdateFlag(.desktopWallpaper)
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
        guard !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults
        else {
            diagLog.debug("Menu bar is hidden by system. \(actionMessage)")
            return false
        }
        guard !appState.activeSpace.isFullscreen else {
            diagLog.debug("Active space is fullscreen. \(actionMessage)")
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

    /// Stores the area of the desktop wallpaper that is under the menu bar
    /// of the given display.
    private func updateDesktopWallpaper(
        for display: CGDirectDisplayID,
        with windows: [WindowInfo]
    ) {
        guard
            let appState,
            appState.appearanceManager.configuration.shapeKind != .noShape
        else {
            desktopWallpaper = nil
            return
        }
        guard
            let menuBarWindow = WindowInfo.menuBarWindow(
                from: windows,
                for: display
            )
        else {
            return
        }
        let wallpaper = ScreenCapture.captureScreenBelowWindow(
            with: menuBarWindow.windowID,
            screenBounds: menuBarWindow.bounds,
            option: .nominalResolution
        )
        if desktopWallpaper?.dataProvider?.data != wallpaper?.dataProvider?.data {
            desktopWallpaper = wallpaper
        }
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(
        for flags: Set<UpdateFlag>,
        windows: [WindowInfo],
        screen: NSScreen
    ) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: screen)
        }
        if flags.contains(.desktopWallpaper) {
            updateDesktopWallpaper(for: screen.displayID, with: windows)
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
            return
        }

        guard let menuBarHeight = owningScreen.getMenuBarHeight() else {
            return
        }

        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )

        alphaValue = 0
        setFrame(newFrame, display: true)
        orderFrontRegardless()

        updateFlags = [.applicationMenuFrame, .desktopWallpaper]

        if !appState.menuBarManager.isMenuBarHiddenBySystem {
            animator().alphaValue = 1
        }
    }

    override func close() {
        missionControlProbeWindow.close()
        super.close()
        #if DEBUG
            diagLog.debug("Overlay panel closed. Active windows: \(NSApplication.shared.windows.count)")
        #endif
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

    private var cancellables = Set<AnyCancellable>()

    /// Cached menu bar item windows, updated by publishers instead of
    /// being queried synchronously during each `draw(_:)` call.
    private var cachedItemWindows: [WindowInfo] = []

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The currently displayed configuration.
    private var configuration: MenuBarAppearancePartialConfiguration {
        previewConfiguration ?? fullConfiguration.current
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
                    .removeDuplicates()
                    .assign(to: &$fullConfiguration)

                appState.appearanceManager.$previewConfiguration
                    .removeDuplicates()
                    .assign(to: &$previewConfiguration)

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
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    self?.updateCachedItemWindows()
                    self?.needsDisplay = true
                }
                .store(in: &c)
            // Redraw whenever the desktop wallpaper changes.
            overlayPanel.$desktopWallpaper
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
        }

        // Redraw whenever the configurations change.
        $fullConfiguration.replace(with: ())
            .merge(with: $previewConfiguration.replace(with: ()))
            .sink { [weak self] _ in
                guard let self, let panel = self.overlayPanel else {
                    return
                }
                self.needsDisplay = true
                panel.insertUpdateFlag(.desktopWallpaper)
            }
            .store(in: &c)

        cancellables = c

        // Populate the cache immediately so the first draw has data.
        updateCachedItemWindows()
    }

    /// Refreshes the cached menu bar item windows from the Window Server.
    private func updateCachedItemWindows() {
        guard let screen = overlayPanel?.owningScreen else {
            cachedItemWindows = []
            return
        }
        cachedItemWindows = MenuBarItem.getMenuBarItemWindows(
            on: screen.displayID,
            option: .onScreen
        )
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
                var maxX = overlayPanel?.applicationMenuFrame?.width,
                maxX > 0
            else {
                return .zero
            }
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
                width: max(0, maxX - fullConfiguration.leftMargin),
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
        case .noTint:
            if fullConfiguration.showsMenuBarBackground {
                NSColor.black.withAlphaComponent(0.2).setFill()
                rect.fill()
            }
        case .solid:
            if let tintColor = NSColor(cgColor: configuration.tintColor)?
                .withAlphaComponent(0.2)
            {
                tintColor.setFill()
                rect.fill()
            }
        case .gradient:
            if let tintGradient = configuration.tintGradient.withAlpha(0.2)
                .nsGradient(using: .displayP3)
            {
                tintGradient.draw(in: rect, angle: 0)
            }
        }
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
            }

        var hasBorder = false

        switch fullConfiguration.shapeKind {
        case .noShape:
            if configuration.hasShadow {
                let gradient = NSGradient(
                    colors: [
                        NSColor(white: 0.0, alpha: 0.0),
                        NSColor(white: 0.0, alpha: 0.2),
                    ]
                )
                let shadowBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: bounds.width,
                    height: 5
                )
                gradient?.draw(in: shadowBounds, angle: 90)
            }

            drawTint(in: drawableBounds)

            if configuration.hasBorder {
                let borderBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY + 5,
                    width: bounds.width,
                    height: configuration.borderWidth
                )
                NSColor(cgColor: configuration.borderColor)?.setFill()
                NSBezierPath(rect: borderBounds).fill()
            }
        case .full, .split:
            if !fullConfiguration.showsMenuBarBackground,
               let desktopWallpaper = overlayPanel.desktopWallpaper
            {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let invertedClipPath = NSBezierPath(rect: drawableBounds)
                invertedClipPath.append(shapePath.reversed)
                invertedClipPath.setClip()

                context.cgContext.draw(desktopWallpaper, in: drawableBounds)
            }

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

            if configuration.hasBorder {
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

                // HACK: Insetting a path to get an "inside" stroke is surprisingly
                // difficult. We can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped.
                borderPath.lineWidth = configuration.borderWidth * 2
                borderPath.setClip()

                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}
