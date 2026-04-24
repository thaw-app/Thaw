//
//  HIDEventManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
import Cocoa
import Combine
import os

/// Manager that monitors input events and implements the features
/// that are triggered by them, such as showing hidden items on
/// click/hover/scroll.
@MainActor
final class HIDEventManager: ObservableObject {
    private static nonisolated let diagLog = DiagLog(category: "HIDEventManager")

    /// A Boolean value that indicates whether the user is dragging
    /// a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// The shared app state.
    private weak var appState: AppState?

    /// Thread-safe counter for mouse-moved event throttling.
    private nonisolated let mouseMovedThrottleCounter = OSAllocatedUnfairLock(initialState: 0)

    /// Timestamp of the last forwarded app menu click, used to debounce
    /// duplicate events from a single physical interaction.
    private var lastAppMenuClickTime: CFAbsoluteTime = 0

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Timer that periodically checks whether the event tap is still
    /// valid and attempts to recreate it if the Mach port was invalidated.
    private var healthCheckTimer: Timer?

    /// The currently pending show-on-hover delay task.
    private var hoverTask: Task<Void, any Error>?

    /// Identity token for the current hover task so an older task cannot
    /// clear state that belongs to a newer one.
    private var hoverTaskToken: UUID?

    /// A short-lived recovery task that repeatedly re-evaluates show-on-hover
    /// right after the setting is enabled, so the first hover does not depend
    /// on a later mouse-moved event or the periodic health check.
    private var hoverRearmTask: Task<Void, Never>?
    private var hoverRearmTaskToken: UUID?

    /// Tracks the last seen value of showOnHover so the CombineLatest3 sink
    /// can restrict rearm logic to false→true transitions only.
    private var lastShowOnHover: Bool?

    /// The currently pending hover action, used to avoid restarting the same
    /// delay window on every small mouse move inside the same region.
    private var pendingHoverAction: HoverAction?

    /// The pending task that clears the temporary show-on-click guard.
    private var clickTask: Task<Void, Never>?

    /// Identity token for the current click task so a late/re-armed task
    /// cannot call expireShowOnClickGuard after it has been superseded.
    private var clickTaskToken: UUID?

    /// The deadline for the temporary show-on-click protection region.
    private var showOnClickGuardDeadline: ContinuousClock.Instant?

    /// The temporary protected region around the first click that revealed
    /// hidden items. Clicks inside this region are intercepted until the
    /// system double-click window expires.
    private var showOnClickGuardRegion: CGRect?

    /// The display hosting the current protected region.
    private var showOnClickGuardDisplayID: CGDirectDisplayID?

    /// Tracks the state of the swallow/disarm lifecycle for the click guard tap.
    private enum GuardMouseUpState {
        /// No mouse-down has been swallowed; guard tap is idle between clicks.
        case idle
        /// A mouse-down was swallowed; swallow the matching mouse-up but keep
        /// the guard armed afterward (double-click window still open).
        case swallowing
        /// A mouse-down was swallowed and teardown is pending; swallow the
        /// matching mouse-up then fully disarm the guard.
        case swallowingThenDisarm
    }

    private var guardMouseUpState: GuardMouseUpState = .idle

    /// The number of times the manager has been told to stop.
    private var disableCount = 0

    private enum HoverAction {
        case show
        case hide
    }

    /// Timestamp of the last `stopAll()` call, used by the health check
    /// to detect a stuck disabled state.
    private var lastStopTimestamp: ContinuousClock.Instant?

    /// Thread-safe lookup table mapping menu bar window IDs to their bounds.
    /// Rebuilt from itemCache whenever it changes, eliminating
    /// per-event Window Server IPC calls during mouse movement.
    ///
    /// Protected by a lock because the CGEventTap callback reads this array
    /// on the main RunLoop, while writes happen on the main thread via Combine.
    /// Although both currently execute on the main thread, the RunLoop-based
    /// guarantee is implicit — using a lock makes the safety explicit and
    /// protects against future refactoring that might change threading.
    private nonisolated let windowBoundsLock = OSAllocatedUnfairLock(
        initialState: [(windowID: CGWindowID, bounds: CGRect)]()
    )

    /// The window ID of the menu bar item the mouse is currently hovering over,
    /// used to detect when the cursor moves to a different item.
    private var tooltipHoveredWindowID: CGWindowID?

    /// The ID of the display the mouse was last seen on.
    private var lastMouseScreenID: CGDirectDisplayID?

    /// The pending tooltip show task.
    private var tooltipTask: Task<Void, any Error>?

    /// A Boolean value that indicates whether the manager is enabled.
    private var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else {
                return
            }
            if isEnabled {
                for monitor in allMonitors {
                    monitor.start()
                }
                if let appState, needsMouseMovedTap(appState: appState) {
                    mouseMovedTap.start()
                }
            } else {
                for monitor in allMonitors {
                    monitor.stop()
                }
                mouseMovedTap.stop()
                lastMouseScreenID = nil
            }
        }
    }

    // MARK: Monitors

    /// Monitor for mouse down events.
    private(set) lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard let self, isEnabled, let appState else {
            return event
        }
        // Prefer the screen the mouse is physically on so clicks on the external
        // monitor's menu bar are processed against the correct display geometry.
        // Fall back to the active-menu-bar screen when the mouse screen has no
        // visible menu bar (e.g. a fullscreen app is suppressing it), which
        // preserves the original guard against acting on inactive menu bars.
        let mouseScreen = NSScreen.screenWithMouse ?? NSScreen.main
        let screen: NSScreen
        if let s = mouseScreen, s.getMenuBarHeight() != nil {
            screen = s
        } else if let s = bestScreen(appState: appState) {
            screen = s
        } else {
            return event
        }
        switch event.type {
        case .leftMouseDown:
            // Check app menu first - if click is on app menu area, don't trigger
            // show-on-click or smart rehide (the click belongs to the app menu)
            let isAppMenuClick = handleApplicationMenuClickThrough(appState: appState, screen: screen)
            if !isAppMenuClick {
                // Capture the click location synchronously from the event.
                let clickLocation = NSEvent.mouseLocation
                handleShowOnClick(appState: appState, screen: screen, clickLocation: clickLocation, isDoubleClick: event.clickCount > 1)
                handleSmartRehide(with: event, appState: appState, screen: screen)
            }
        case .rightMouseDown:
            handleSecondaryContextMenu(appState: appState, screen: screen)
        default:
            return event
        }
        handlePreventShowOnHover(
            with: event,
            appState: appState,
            screen: screen
        )
        dismissMenuBarTooltip()
        return event
    }

    /// Monitor for mouse up events.
    private(set) lazy var mouseUpMonitor = EventMonitor.universal(
        for: .leftMouseUp
    ) { [weak self] event in
        guard let self, isEnabled else {
            return event
        }
        handleMenuBarItemDragStop()
        return event
    }

    /// Monitor for mouse dragged events.
    private(set) lazy var mouseDraggedMonitor = EventMonitor.universal(
        for: .leftMouseDragged
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleMenuBarItemDragStart(
                with: event,
                appState: appState,
                screen: screen
            )
        }
        return event
    }

    /// Tap for mouse moved events.
    private(set) lazy var mouseMovedTap = EventTap(
        type: .mouseMoved,
        location: .hidEventTap,
        placement: .tailAppendEventTap,
        option: .listenOnly
    ) { [weak self] _, event in
        guard let self, isEnabled else {
            return event
        }

        // Throttling: Only process every 5th event to reduce CPU usage.
        let shouldProcess = mouseMovedThrottleCounter.withLock { count -> Bool in
            count += 1
            if count >= 5 {
                count = 0
                return true
            }
            return false
        }
        guard shouldProcess else {
            return event
        }

        if let appState {
            guard let screen = NSScreen.screenWithMouse ?? NSScreen.main else {
                return event
            }
            let screenID = screen.displayID

            if screenID != lastMouseScreenID {
                lastMouseScreenID = screenID
                appState.menuBarManager.updateControlItemStates(for: screen)
            }

            handleShowOnHover(appState: appState, screen: screen)
            handleMenuBarTooltip(appState: appState, screen: screen)
        }
        return event
    }

    /// Monitor for scroll wheel events.
    private(set) lazy var scrollWheelMonitor = EventMonitor.universal(
        for: .scrollWheel
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleShowOnScroll(with: event, appState: appState, screen: screen)
        }
        return event
    }

    /// Active tap that temporarily swallows clicks in the protected region
    /// after a first show-on-click reveal, so a double-click can still be
    /// recognized even though hidden items have appeared under the cursor.
    private(set) lazy var showOnClickGuardTap = EventTap(
        label: "showOnClickGuardTap",
        types: [.leftMouseDown, .leftMouseUp],
        location: .sessionEventTap,
        placement: .headInsertEventTap,
        option: .defaultTap
    ) { [weak self] _, event in
        guard let self else {
            return event
        }

        expireShowOnClickGuardIfNeeded()

        if event.type == .leftMouseUp, guardMouseUpState != .idle {
            let state = guardMouseUpState
            guardMouseUpState = .idle
            if state == .swallowingThenDisarm {
                disarmShowOnClickGuard()
            }
            return nil
        }

        guard isEnabled, let appState, isShowOnClickGuardActive else {
            return event
        }

        guard event.type == .leftMouseDown else {
            return event
        }

        guard isPointInsideShowOnClickGuardRegion(NSEvent.mouseLocation) else {
            return event
        }

        let clickState = event.getIntegerValueField(.mouseEventClickState)
        if clickState > 1,
           appState.settings.general.showOnClick,
           appState.settings.general.showOnDoubleClick,
           let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
           alwaysHiddenSection.isEnabled
        {
            alwaysHiddenSection.show()
            guardMouseUpState = .swallowingThenDisarm
        } else {
            guardMouseUpState = .swallowing
        }

        return nil
    }

    // MARK: All Monitors

    /// All monitors maintained by the manager.
    private lazy var allMonitors: [any EventMonitorProtocol] = [
        mouseDownMonitor,
        mouseUpMonitor,
        mouseDraggedMonitor,
        scrollWheelMonitor,
    ]

    // MARK: Setup

    /// Sets up the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        startAll()
        configureCancellables()
    }

    /// Whether the mouse-moved event tap should be active based on current settings.
    private func needsMouseMovedTap(appState: AppState) -> Bool {
        appState.settings.general.showOnHover ||
            appState.settings.advanced.showMenuBarTooltips ||
            appState.settings.displaySettings.isAlwaysShowEnabledOnAnyDisplay
    }

    /// Maximum width a normal menu bar item can have. Windows wider than
    /// this are expanded section-divider control items used to push hidden
    /// items off-screen and must be excluded from the bounds lookup.
    private static let maxReasonableItemWidth: CGFloat = 500

    /// Rebuilds the window bounds lookup table from the current item cache.
    ///
    /// Includes ALL menu bar item windows (both managed and unmanaged) so that
    /// clicks on unmanaged items like Clock and Control Center are correctly
    /// detected as being on a menu bar item, not on empty space.
    private func rebuildWindowBoundsLookup(from cache: MenuBarItemManager.ItemCache) {
        var knownWindowIDs = Set<CGWindowID>()
        var buffer = [(windowID: CGWindowID, bounds: CGRect)]()

        // Query all on-screen menu bar item windows first to get fresh bounds.
        // This ensures we have accurate bounds even if the cache is stale.
        let allWindowIDs = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ])
        for windowID in allWindowIDs {
            if let bounds = Bridging.getWindowBounds(for: windowID) {
                guard bounds.width <= Self.maxReasonableItemWidth else {
                    continue
                }
                buffer.append((windowID: windowID, bounds: bounds))
                knownWindowIDs.insert(windowID)
            }
        }

        // Add any managed items that might not be in the Window Server list yet.
        // This is a fallback for items that might not be reported by the Window Server.
        let items = cache.managedItems
        for item in items where item.isOnScreen && !knownWindowIDs.contains(item.windowID) {
            guard item.bounds.width <= Self.maxReasonableItemWidth else {
                continue
            }
            buffer.append((windowID: item.windowID, bounds: item.bounds))
            knownWindowIDs.insert(item.windowID)
        }

        let entries = buffer
        windowBoundsLock.withLock { $0 = entries }
    }

    /// Rebuilds the bounds lookup using the current on-screen menu bar layout.
    ///
    /// Section show/hide changes often keep the same window IDs while moving
    /// items on or off screen. Rebuilding from the last item cache in those
    /// moments can leave hit testing with stale geometry, so use a direct
    /// Window Server snapshot instead.
    private func rebuildWindowBoundsLookupFromCurrentLayout() {
        let allWindowIDs = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ])

        let entries = allWindowIDs.compactMap { windowID -> (windowID: CGWindowID, bounds: CGRect)? in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return nil
            }

            guard bounds.width <= Self.maxReasonableItemWidth else {
                return nil
            }

            return (windowID: windowID, bounds: bounds)
        }

        windowBoundsLock.withLock { $0 = entries }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            // Start or stop the mouse-moved tap when show-on-hover,
            // menu-bar-tooltips, or per-display configurations change.
            Publishers.CombineLatest3(
                appState.settings.general.$showOnHover,
                appState.settings.advanced.$showMenuBarTooltips,
                appState.settings.displaySettings.$configurations
            )
            .sink { [weak self] showOnHover, _, _ in
                guard let self, isEnabled else {
                    return
                }
                if needsMouseMovedTap(appState: appState) {
                    mouseMovedTap.start()
                } else {
                    mouseMovedTap.stop()
                }

                defer { lastShowOnHover = showOnHover }

                if !showOnHover {
                    hoverRearmTask?.cancel()
                    hoverRearmTask = nil
                    hoverRearmTaskToken = nil
                    hoverTask?.cancel()
                    hoverTask = nil
                    hoverTaskToken = nil
                    pendingHoverAction = nil
                    return
                }

                // Only rearm when showOnHover transitions false→true; skip the
                // rearm path when other inputs (tooltips, display config) change
                // while showOnHover was already enabled.
                guard lastShowOnHover != true else {
                    return
                }

                appState.menuBarManager.showOnHoverAllowed = true
                hoverRearmTask?.cancel()
                hoverRearmTask = nil
                hoverRearmTaskToken = nil
                hoverTask?.cancel()
                hoverTask = nil
                hoverTaskToken = nil
                pendingHoverAction = nil
                scheduleHoverRearmChecks(appState: appState)
            }
            .store(in: &c)

            // Rebuild the window bounds lookup whenever the item cache changes.
            // This replaces per-event Window Server IPC calls with an in-memory lookup.
            appState.itemManager.$itemCache
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] cache in
                    self?.rebuildWindowBoundsLookup(from: cache)
                }
                .store(in: &c)

            // When any section's control item state changes, the menu bar layout shifts.
            // Merge all sections into a single publisher so only one cache refresh fires
            // per layout change batch, regardless of how many sections change at once.
            // Drop the initial emission per publisher so MergeMany no longer relies on
            // a global dropFirst count and rebuildWindowBoundsLookupFromCurrentLayout()
            // runs only for real updates.
            Publishers.MergeMany(
                appState.menuBarManager.sections.map {
                    $0.controlItem.$state
                        .dropFirst()
                        .replace(with: ())
                }
            )
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.rebuildWindowBoundsLookupFromCurrentLayout()
            }
            .store(in: &c)

            // Clear bounds lookup on display configuration changes.
            // The item cache will be refreshed shortly after.
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
            .sink { [weak self] _ in
                NSScreen.invalidateMenuBarHeightCache()
                NSScreen.cleanupDisconnectedDisplayCaches()
                self?.windowBoundsLock.withLock { $0.removeAll() }
            }
            .store(in: &c)
        }

        cancellables = c

        // Build the initial bounds lookup from the current cache.
        if let appState {
            rebuildWindowBoundsLookup(from: appState.itemManager.itemCache)
        }

        // Periodically check that the mouseMovedTap is still alive.
        // macOS can invalidate the Mach port under resource pressure or
        // when accessibility permissions change. If it becomes invalid,
        // ensureValid() will recreate it.
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performHealthCheck()
            }
        }
        healthCheckTimer?.tolerance = 5
    }

    /// Checks the health of event monitors and taps, and attempts
    /// recovery if needed.
    private func performHealthCheck() {
        // Detect a stuck disabled state. If disableCount > 0 and we've
        // been disabled for longer than any legitimate operation would
        // take (e.g. a move or click), the count is likely imbalanced
        // due to a cancelled Task or unexpected error. Force recovery.
        if !isEnabled, disableCount > 0, let lastStop = lastStopTimestamp {
            let elapsed = ContinuousClock.now - lastStop
            if elapsed > .seconds(30) {
                Self.diagLog.error(
                    """
                    Event manager stuck in disabled state for \
                    \(elapsed) with disableCount=\
                    \(self.disableCount), forcing recovery
                    """
                )
                disableCount = 0
                isEnabled = true
                lastStopTimestamp = nil
            }
        }

        guard isEnabled else { return }

        // Check all NSEvent-based monitors and restart any that stopped running.
        // This handles cases where macOS silently invalidates monitors due to
        // accessibility permission changes, system resource pressure, or other
        // unexpected conditions.
        for monitor in allMonitors {
            monitor.ensureRunning()
        }

        // Check the mouseMovedTap if it should be active.
        if let appState,
           needsMouseMovedTap(appState: appState),
           mouseMovedTap.ensureValid(),
           !mouseMovedTap.isEnabled
        {
            Self.diagLog.warning("mouseMovedTap was valid but not enabled, re-enabling")
            mouseMovedTap.start()
        }
    }

    // MARK: Start/Stop

    /// Starts all monitors.
    func startAll() {
        if disableCount > 0 {
            disableCount -= 1
        }
        if disableCount == 0 {
            isEnabled = true
            lastStopTimestamp = nil
        }
    }

    /// Stops all monitors.
    func stopAll() {
        if disableCount == 0 {
            isEnabled = false
        }
        disableCount += 1
        lastStopTimestamp = .now
        hoverRearmTask?.cancel()
        hoverRearmTask = nil
        hoverRearmTaskToken = nil
        hoverTask?.cancel()
        hoverTask = nil
        hoverTaskToken = nil
        pendingHoverAction = nil
        disarmShowOnClickGuard()
        dismissMenuBarTooltip()
    }
}

// MARK: - Handler Methods

extension HIDEventManager {
    private func isMouseNearMenuBar(screen: NSScreen, verticalPadding: CGFloat = 80) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return false
        }

        return mouseLocation.x >= screen.frame.minX
            && mouseLocation.x <= screen.frame.maxX
            && mouseLocation.y <= screen.frame.maxY
            && mouseLocation.y >= screen.frame.maxY - menuBarHeight - verticalPadding
    }

    private func scheduleHoverRearmChecks(appState: AppState) {
        let taskToken = UUID()
        hoverRearmTaskToken = taskToken
        hoverRearmTask = Task { @MainActor [weak self, weak appState] in
            guard let self, let appState else {
                return
            }

            defer {
                if hoverRearmTaskToken == taskToken {
                    hoverRearmTask = nil
                    hoverRearmTaskToken = nil
                }
            }

            for attempt in 0 ..< 12 {
                do {
                    try await Task.sleep(for: attempt == 0 ? .milliseconds(50) : .milliseconds(200))
                } catch {
                    return
                }

                guard
                    hoverRearmTaskToken == taskToken,
                    isEnabled,
                    appState.settings.general.showOnHover,
                    appState.menuBarManager.showOnHoverAllowed
                else {
                    return
                }

                if needsMouseMovedTap(appState: appState) {
                    _ = mouseMovedTap.ensureValid()
                    mouseMovedTap.start()
                }

                guard let screen = NSScreen.screenWithMouse ?? bestScreen(appState: appState) else {
                    continue
                }

                guard isMouseNearMenuBar(screen: screen) else {
                    return
                }

                handleShowOnHover(appState: appState, screen: screen)

                if pendingHoverAction == .show ||
                    !(appState.menuBarManager.section(withName: .hidden)?.isHidden ?? true)
                {
                    return
                }
            }
        }
    }

    // MARK: Handle Show On Click

    private func handleShowOnClick(appState: AppState, screen: NSScreen, clickLocation: CGPoint, isDoubleClick: Bool = false) {
        guard isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) else {
            return
        }

        if isDoubleClick {
            guard
                appState.settings.general.showOnClick,
                appState.settings.general.showOnDoubleClick
            else {
                return
            }
            Task {
                if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                   alwaysHiddenSection.isEnabled
                {
                    alwaysHiddenSection.show()
                }
            }
        } else {
            guard appState.settings.general.showOnClick else {
                return
            }

            if NSEvent.modifierFlags == .control {
                handleSecondaryContextMenu(appState: appState, screen: screen)
                return
            }

            if NSEvent.modifierFlags == .option {
                if appState.settings.advanced.useOptionClickToShowAlwaysHiddenSection,
                   let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                   alwaysHiddenSection.isEnabled
                {
                    Task { alwaysHiddenSection.show() }
                }
                return
            }

            if let hiddenSection = appState.menuBarManager.section(withName: .hidden),
               hiddenSection.isEnabled
            {
                let shouldArmGuard =
                    appState.settings.general.showOnDoubleClick
                        && hiddenSection.isHidden
                        && (appState.menuBarManager.section(withName: .alwaysHidden)?.isEnabled ?? false)

                // Arm the guard synchronously before toggling so the CGEventTap
                // is active before any second click can arrive; a Task hop would
                // leave a window where the tap is not yet started.
                if shouldArmGuard {
                    armShowOnClickGuard(screen: screen, at: clickLocation)
                } else {
                    disarmShowOnClickGuard()
                }

                Task { hiddenSection.toggle() }
            }
        }
    }

    private func armShowOnClickGuard(screen: NSScreen, at clickLocation: CGPoint) {
        guard let menuBarHeight = screen.getMenuBarHeight() else {
            disarmShowOnClickGuard()
            return
        }

        let protectionWidth = max(44, menuBarHeight * 2)
        let protectionHeight = menuBarHeight + 6
        let minY = screen.frame.maxY - menuBarHeight - 3
        showOnClickGuardRegion = CGRect(
            x: clickLocation.x - protectionWidth / 2,
            y: minY,
            width: protectionWidth,
            height: protectionHeight
        )
        showOnClickGuardDisplayID = screen.displayID
        showOnClickGuardDeadline = .now + .seconds(NSEvent.doubleClickInterval)
        guardMouseUpState = .idle

        showOnClickGuardTap.start()

        clickTask?.cancel()
        let token = UUID()
        clickTaskToken = token
        clickTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            } catch {
                return
            }
            await MainActor.run {
                guard self?.clickTaskToken == token else { return }
                self?.expireShowOnClickGuard()
            }
        }
    }

    private func expireShowOnClickGuard() {
        if guardMouseUpState != .idle {
            // Mouse button is still held; defer full teardown until the
            // swallowed mouse-up arrives so the tap stays active.
            guardMouseUpState = .swallowingThenDisarm
            showOnClickGuardDeadline = nil
            showOnClickGuardRegion = nil
            showOnClickGuardDisplayID = nil
            clickTask = nil
            clickTaskToken = nil
            return
        }

        disarmShowOnClickGuard()
    }

    private func disarmShowOnClickGuard() {
        // If we're waiting for a swallowed mouse-up, defer disarming until it arrives.
        // This keeps the CGEventTap active until the swallowed mouse-up is processed
        // and prevents a stray mouse-up being delivered to the system.
        if guardMouseUpState != .idle {
            guardMouseUpState = .swallowingThenDisarm
            return
        }

        clickTask?.cancel()
        clickTask = nil
        clickTaskToken = nil
        showOnClickGuardDeadline = nil
        showOnClickGuardRegion = nil
        showOnClickGuardDisplayID = nil
        guardMouseUpState = .idle
        showOnClickGuardTap.stop()
    }

    /// Tears down the guard if its deadline has passed. Call this before
    /// reading `isShowOnClickGuardActive` in contexts that need to react
    /// to expiry (e.g. the tap callback, hit-test helpers).
    private func expireShowOnClickGuardIfNeeded() {
        guard let deadline = showOnClickGuardDeadline, deadline <= .now else {
            return
        }
        expireShowOnClickGuard()
    }

    /// Pure read — returns whether the guard is currently armed and within its
    /// deadline. Does not mutate state; call `expireShowOnClickGuardIfNeeded()`
    /// first if expiry should be applied.
    private var isShowOnClickGuardActive: Bool {
        guard let deadline = showOnClickGuardDeadline else {
            return false
        }
        return deadline > .now && showOnClickGuardRegion != nil
    }

    private func isPointInsideShowOnClickGuardRegion(_ point: CGPoint) -> Bool {
        expireShowOnClickGuardIfNeeded()
        guard isShowOnClickGuardActive,
              let region = showOnClickGuardRegion,
              let displayID = showOnClickGuardDisplayID
        else {
            return false
        }

        guard NSScreen.screenWithMouse?.displayID == displayID else {
            return false
        }

        return region.contains(point)
    }

    // MARK: Handle Smart Rehide

    private func handleSmartRehide(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            appState.settings.general.autoRehide,
            case .smart = appState.settings.general.rehideStrategy
        else {
            return
        }

        // Make sure clicking the Ice icon doesn't trigger rehide.
        if let iceIcon = appState.menuBarManager.controlItem(withName: .visible) {
            guard event.window !== iceIcon.window else {
                return
            }
        }

        // Only continue if the click is not inside the Thaw Bar, at
        // least one section is visible, and the mouse is not inside
        // the menu bar.
        guard
            event.window !== appState.menuBarManager.iceBarPanel,
            appState.menuBarManager.hasVisibleSection,
            !isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        let initialSpaceID = Bridging.getActiveSpaceID()

        Task {
            // Give the window under the mouse a chance to focus.
            try await Task.sleep(for: .milliseconds(250))

            // Don't bother checking the window if the click caused
            // a space change.
            if Bridging.getActiveSpaceID() != initialSpaceID {
                for section in appState.menuBarManager.sections {
                    section.hide()
                }
                return
            }

            // Get the window that was clicked.
            guard
                let mouseLocation = MouseHelpers.locationCoreGraphics,
                let windowUnderMouse = WindowInfo.createWindows(
                    option: .onScreen
                )
                .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })
                .first(where: {
                    $0.bounds.contains(mouseLocation)
                        && $0.title?.isEmpty == false
                }),
                let owningApplication = windowUnderMouse.owningApplication
            else {
                return
            }

            // Note: The Dock is an exception to the following check.
            if owningApplication.bundleIdentifier != "com.apple.dock" {
                // Only continue if the clicked app is active, and has
                // a regular activation policy.
                guard
                    owningApplication.isActive,
                    owningApplication.activationPolicy == .regular
                else {
                    return
                }
            }

            // Check if any menu bar item has a menu open.
            if await appState.itemManager.isAnyMenuBarItemMenuOpen() {
                return
            }

            // All checks have passed, hide the sections.
            for section in appState.menuBarManager.sections {
                section.hide()
            }
        }
    }

    // MARK: Handle Secondary Context Menu

    private func handleSecondaryContextMenu(
        appState: AppState,
        screen: NSScreen
    ) {
        Task {
            guard
                appState.settings.advanced.enableSecondaryContextMenu,
                isMouseInsideEmptyMenuBarSpace(
                    appState: appState,
                    screen: screen
                ),
                let mouseLocation = MouseHelpers.locationAppKit
            else {
                return
            }
            // Delay prevents the menu from immediately closing.
            try await Task.sleep(for: .milliseconds(100))
            appState.menuBarManager.showSecondaryContextMenu(at: mouseLocation)
        }
    }

    // MARK: Handle Application Menu Click-Through

    /// Checks if the click is on an application menu (File, Edit, View, etc.)
    /// and forwards clicks when expanded section-divider windows block them.
    ///
    /// After a profile change with ThawBar active, the Window Server tracks
    /// the expanded control item windows and routes clicks to them instead
    /// of the application menus underneath. This method uses AX to locate
    /// the correct menu bar item, then posts a synthetic click directly to
    /// the owning application's PID.
    ///
    /// - Returns: `true` if the click was on an application menu area (regardless
    ///   of whether forwarding was needed), `false` otherwise. Callers should skip
    ///   show-on-click behavior when this returns `true`.
    @discardableResult
    private func handleApplicationMenuClickThrough(
        appState: AppState,
        screen: NSScreen
    ) -> Bool {
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let mouseLocation = MouseHelpers.locationCoreGraphics
        else {
            return false
        }

        // Capture the AX frame before any UI changes; the frame is needed
        // for click forwarding and can become unavailable after closing/hiding UI.
        guard let initialFrame = applicationMenuItemFrame(at: mouseLocation) else {
            return false
        }

        // Click is on app menu area - check if we need to forward it
        let hasExpandedDivider = appState.menuBarManager.sections.contains { section in
            section.controlItem.isSectionDivider && section.controlItem.state == .hideSection
        }
        guard hasExpandedDivider else {
            // No expanded divider blocking the click, but still on app menu
            return true
        }

        let expandedWindowCoversClick = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ]).contains { windowID in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return false
            }
            return bounds.width > Self.maxReasonableItemWidth && bounds.contains(mouseLocation)
        }
        guard expandedWindowCoversClick else {
            // On app menu but not covered by expanded window
            return true
        }

        // Forward the click to the app menu
        appState.menuBarManager.iceBarPanel.close()
        for section in appState.menuBarManager.sections {
            section.hide()
        }

        guard let frontApp = NSWorkspace.shared.menuBarOwningApplication else {
            return true
        }

        // Reuse the originally observed frame for click calculation.
        let frame = initialFrame

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAppMenuClickTime >= 0.3 else { return true }
        lastAppMenuClickTime = now

        let clickPoint = CGPoint(x: frame.midX, y: frame.midY)
        let pid = frontApp.processIdentifier

        guard let source = CGEventSource(stateID: .hidSystemState) else { return true }
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        )
        mouseDown?.postToPid(pid)
        mouseUp?.postToPid(pid)
        return true
    }

    // MARK: Handle Menu Bar Item Drag Stop

    private func handleMenuBarItemDragStop() {
        if isDraggingMenuBarItem {
            isDraggingMenuBarItem = false

            // Record the external move so caching is suppressed for 1s and order
            // restoration is suppressed for 2s,
            // then schedule a cache update to pick up the user's new item positions.
            if let appState {
                appState.itemManager.recordExternalMoveOperation()
                Task { [weak appState] in
                    try? await Task.sleep(for: .milliseconds(500))
                    await appState?.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                }
            }
        }
    }

    // MARK: Handle Menu Bar Item Drag Start

    private func handleMenuBarItemDragStart(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            !isDraggingMenuBarItem,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        isDraggingMenuBarItem = true

        if appState.settings.advanced.showAllSectionsOnUserDrag {
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .showSection
            }
        }
    }

    // MARK: Handle Show On Hover

    private func handleShowOnHover(appState: AppState, screen: NSScreen) {
        // Make sure the "ShowOnHover" feature is enabled and allowed.
        guard
            appState.settings.general.showOnHover,
            appState.menuBarManager.showOnHoverAllowed
        else {
            return
        }

        // Only continue if we have a hidden section (we should).
        guard
            let hiddenSection = appState.menuBarManager.section(
                withName: .hidden
            )
        else {
            return
        }

        let delay = appState.settings.advanced.showOnHoverDelay

        if hiddenSection.isHidden {
            guard
                isMouseInsideEmptyMenuBarSpace(
                    appState: appState,
                    screen: screen
                )
            else {
                if pendingHoverAction == .show {
                    hoverTask?.cancel()
                    hoverTask = nil
                    hoverTaskToken = nil
                    pendingHoverAction = nil
                }
                return
            }
            guard pendingHoverAction != .show else {
                return
            }
            hoverTask?.cancel()
            pendingHoverAction = .show
            let taskToken = UUID()
            hoverTaskToken = taskToken
            hoverTask = Task {
                defer {
                    if hoverTaskToken == taskToken {
                        hoverTask = nil
                        hoverTaskToken = nil
                        if pendingHoverAction == .show {
                            pendingHoverAction = nil
                        }
                    }
                }
                try await Task.sleep(for: .seconds(delay))
                // Make sure the manager is still enabled and the mouse is still inside.
                guard
                    isEnabled,
                    isMouseInsideEmptyMenuBarSpace(
                        appState: appState,
                        screen: screen
                    )
                else {
                    return
                }
                hiddenSection.show()
            }
        } else {
            guard
                !isMouseInsideMenuBar(appState: appState, screen: screen),
                !isMouseInsideIceBar(appState: appState)
            else {
                if pendingHoverAction == .hide {
                    hoverTask?.cancel()
                    hoverTask = nil
                    hoverTaskToken = nil
                    pendingHoverAction = nil
                }
                return
            }
            guard pendingHoverAction != .hide else {
                return
            }
            hoverTask?.cancel()
            pendingHoverAction = .hide
            let taskToken = UUID()
            hoverTaskToken = taskToken
            hoverTask = Task {
                defer {
                    if hoverTaskToken == taskToken {
                        hoverTask = nil
                        hoverTaskToken = nil
                        if pendingHoverAction == .hide {
                            pendingHoverAction = nil
                        }
                    }
                }
                try await Task.sleep(for: .seconds(delay))
                // Make sure the manager is still enabled and the mouse is still outside.
                guard
                    isEnabled,
                    !isMouseInsideMenuBar(appState: appState, screen: screen),
                    !isMouseInsideIceBar(appState: appState)
                else {
                    return
                }
                hiddenSection.hide()
            }
        }
    }

    // MARK: Handle Prevent Show On Hover

    private func handlePreventShowOnHover(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            appState.settings.general.showOnHover,
            !appState.settings.displaySettings.useIceBar(for: screen.displayID)
        else {
            return
        }

        guard isMouseInsideMenuBar(appState: appState, screen: screen) else {
            return
        }

        if isMouseInsideMenuBarItem(appState: appState, screen: screen) {
            switch event.type {
            case .leftMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                if isMouseInsideIceIcon(appState: appState) {
                    break
                }
                return
            case .rightMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                return
            default:
                return
            }
        } else if isMouseInsideApplicationMenuClickRegion(
            appState: appState,
            screen: screen
        ) == true {
            return
        }

        // Mouse is inside the menu bar, outside an item or application
        // menu, so it must be inside an empty menu bar space.
        appState.menuBarManager.showOnHoverAllowed = false
    }

    // MARK: Handle Show On Scroll

    private func handleShowOnScroll(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            appState.settings.general.showOnScroll,
            isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen),
            let hiddenSection = appState.menuBarManager.section(
                withName: .hidden
            )
        else {
            return
        }

        let averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2

        if averageDelta > 5 {
            hiddenSection.show()
        } else if averageDelta < -5 {
            hiddenSection.hide()
        }
    }
}

// MARK: - Helper Methods

extension HIDEventManager {
    /// Returns the best screen to use for hover, scroll, and tooltip calculations.
    ///
    /// Always returns the screen that currently owns the active menu bar.
    /// This prevents showing the hidden section or IceBar on a monitor
    /// whose menu bar is inactive (e.g. when another monitor has a
    /// fullscreen app), where clicking icons would have no effect.
    ///
    /// For mouse-down events, `mouseDownMonitor` resolves the screen from
    /// `NSScreen.screenWithMouse` instead so that clicks on a secondary
    /// display's menu bar are evaluated against the correct display geometry.
    func bestScreen(appState _: AppState) -> NSScreen? {
        NSScreen.screenWithActiveMenuBar ?? NSScreen.main
    }

    // MARK: Menu Bar Tooltips

    /// Shows a tooltip for the menu bar item under the cursor, if enabled.
    private func handleMenuBarTooltip(appState: AppState, screen: NSScreen) {
        guard ScreenCapture.cachedCheckPermissions() else {
            return
        }

        guard appState.settings.advanced.showMenuBarTooltips else {
            return
        }

        guard isMouseInsideMenuBar(appState: appState, screen: screen) else {
            dismissMenuBarTooltip()
            return
        }

        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            dismissMenuBarTooltip()
            return
        }

        // Find the specific window under the cursor using the cached bounds lookup.
        // This avoids per-event IPC calls to the Window Server.
        let entries = windowBoundsLock.withLock { $0 }
        let hoveredEntry = entries.first(where: { $0.bounds.contains(mouseLocation) })

        guard let hoveredEntry else {
            dismissMenuBarTooltip()
            return
        }

        let hoveredID = hoveredEntry.windowID

        // If we're still over the same item, nothing to do.
        if hoveredID == tooltipHoveredWindowID {
            return
        }

        // Moved to a different item — cancel the old tooltip and start a new delay.
        dismissMenuBarTooltip()
        tooltipHoveredWindowID = hoveredID

        let cachedBounds = hoveredEntry.bounds
        let delay = appState.settings.advanced.tooltipDelay
        tooltipTask = Task {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            try Task.checkCancellation()

            // Re-read from the lock to pick up any cache rebuilds during the delay.
            let freshEntries = windowBoundsLock.withLock { $0 }
            let positionBounds = freshEntries.first(where: { $0.windowID == hoveredID })?.bounds ?? cachedBounds

            // Look up the item from the cache by window ID.
            let allItems = appState.itemManager.itemCache.managedItems
            let displayName: String
            if let item = allItems.first(where: { $0.windowID == hoveredID }) {
                displayName = item.displayName
            } else if appState.menuBarManager.sections.contains(where: {
                $0.controlItem.window?.windowNumber == Int(hoveredID)
            }) {
                displayName = Constants.displayName
            } else {
                return
            }

            // Position the tooltip below the item, centered horizontally.
            // Item bounds are in CoreGraphics coordinates (top-left origin);
            // convert to AppKit (bottom-left origin) for the panel.
            guard let primaryScreen = NSScreen.screens.first else { return }
            let appKitOrigin = CGPoint(
                x: positionBounds.midX,
                y: primaryScreen.frame.height - positionBounds.maxY
            )

            CustomTooltipPanel.shared.show(
                text: displayName,
                near: appKitOrigin,
                in: screen,
                owner: "menuBar"
            )
        }
    }

    /// Cancels any pending tooltip and hides the tooltip panel.
    /// Only dismisses the panel if it was shown by the menu bar tooltip handler.
    private func dismissMenuBarTooltip() {
        tooltipTask?.cancel()
        tooltipTask = nil
        tooltipHoveredWindowID = nil
        CustomTooltipPanel.shared.dismiss(owner: "menuBar")
    }

    // MARK: Mouse Location Helpers

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the menu bar.
    func isMouseInsideMenuBar(appState _: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return false
        }

        // Infer the menu bar frame from the screen frame and menu bar height.
        return mouseLocation.x >= screen.frame.minX
            && mouseLocation.x <= screen.frame.maxX
            && mouseLocation.y <= screen.frame.maxY
            && mouseLocation.y >= screen.frame.maxY - menuBarHeight
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the current application menu.
    func isMouseInsideApplicationMenu(appState _: AppState, screen: NSScreen)
        -> Bool
    {
        guard
            let mouseLocation = MouseHelpers.locationCoreGraphics,
            var applicationMenuFrame = screen.getApplicationMenuFrame()
        else {
            return false
        }
        applicationMenuFrame.size.width +=
            applicationMenuFrame.origin.x - screen.frame.origin.x
        applicationMenuFrame.origin.x = screen.frame.origin.x
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// Returns `true` when the current mouse location hits a cached menu bar item
    /// bounds entry. This is the fast path used by hover/click hit testing.
    private func isMouseInsideCachedMenuBarItem() -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }

        let entries = windowBoundsLock.withLock { $0 }
        return entries.contains { entry in
            entry.bounds.contains(mouseLocation)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    func isMouseInsideMenuBarItem(appState _: AppState, screen _: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }

        // Use the pre-built bounds lookup table, which is rebuilt
        // whenever the item cache changes. This avoids per-event
        // IPC calls to the Window Server.
        let cacheHit = isMouseInsideCachedMenuBarItem()

        // If we found a hit in the cache, return early.
        if cacheHit {
            return true
        }

        // If the cache missed, query the Window Server directly as a fallback.
        // This handles the case where items were just shown and the cache
        // hasn't been updated yet.
        let windowIDs = Bridging.getMenuBarWindowList(option: [
            .onScreen, .activeSpace, .itemsOnly,
        ])
        return windowIDs.contains { windowID in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return false
            }
            guard bounds.width <= Self.maxReasonableItemWidth else {
                return false
            }
            return bounds.contains(mouseLocation)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the screen's notch, if it has one.
    ///
    /// If the screen does not have a notch, this property returns `false`.
    func isMouseInsideNotch(appState _: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            var frameOfNotch = screen.frameOfNotch
        else {
            return false
        }
        frameOfNotch.size.height += 1
        return frameOfNotch.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of an empty space in the menu bar.
    func isMouseInsideEmptyMenuBarSpace(appState: AppState, screen: NSScreen)
        -> Bool
    {
        // Perform cheap geometric checks first.
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            !isMouseInsideNotch(appState: appState, screen: screen)
        else {
            return false
        }

        // Then perform expensive Window Server checks.
        //
        // Always exclude the concrete application-menu click region from empty-space
        // detection; the function `isMouseInsideApplicationMenuClickRegion` checks whether
        // the mouse is over a concrete menu item using AX hit-testing, while
        // `handleApplicationMenuClickThrough` separately handles left-click forwarding
        // to the application menu. When AX hit-testing is indeterminate (returns nil),
        // fall back to cheap geometric detection to avoid misclassifying the app menu
        // area as empty space.
        let appMenuResult = isMouseInsideApplicationMenuClickRegion(
            appState: appState,
            screen: screen
        )

        // Use the AX result when available; fall back to geometric detection
        // when hit-testing is indeterminate (e.g., due to expanded section-divider
        // windows interfering with AX queries).
        let isInAppMenu: Bool
        if let result = appMenuResult {
            isInAppMenu = result
        } else {
            isInAppMenu = isMouseInsideApplicationMenu(appState: appState, screen: screen)
        }

        return !isInAppMenu
            && !isMouseInsideMenuBarItem(appState: appState, screen: screen)
            && !isMouseInsideIceIcon(appState: appState)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Thaw Bar panel.
    func isMouseInsideIceBar(appState: AppState) -> Bool {
        guard let mouseLocation = MouseHelpers.locationAppKit else {
            return false
        }
        let panel = appState.menuBarManager.iceBarPanel
        // Pad the frame to be more forgiving if the user accidentally
        // moves their mouse outside of the Thaw Bar.
        let paddedFrame = panel.frame.insetBy(dx: -15, dy: -15)
        return paddedFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice icon.
    func isMouseInsideIceIcon(appState: AppState) -> Bool {
        guard
            let visibleSection = appState.menuBarManager.section(
                withName: .visible
            ),
            let iceIconFrame = visibleSection.controlItem.frame,
            let mouseLocation = MouseHelpers.locationAppKit
        else {
            return false
        }
        return iceIconFrame.contains(mouseLocation)
    }

    /// Returns whether the cursor is inside the same application-menu region
    /// that the click-through path treats as belonging to the app menu.
    /// Returns `nil` when the AX result is indeterminate (AX queries failed),
    /// `true` when the cursor is inside a menu item, and `false` when AX
    /// queries succeeded but no menu item contains the cursor.
    private func isMouseInsideApplicationMenuClickRegion(
        appState: AppState,
        screen: NSScreen
    ) -> Bool? {
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let mouseLocation = MouseHelpers.locationCoreGraphics
        else {
            return false
        }

        // Query AX to determine if the cursor is inside a menu item.
        // Distinguish between "AX indeterminate" (nil) and "AX succeeded but no hit" (false).
        guard
            let frontApp = NSWorkspace.shared.menuBarOwningApplication,
            let axApp = AXHelpers.application(for: frontApp),
            let menuBar: UIElement = try? axApp.attribute(.menuBar)
        else {
            // AX is indeterminate - can't determine if we're in app menu.
            return nil
        }

        // AX queries succeeded - check if cursor is inside any menu item.
        for child in AXHelpers.children(for: menuBar) {
            guard let frame = AXHelpers.frame(for: child) else {
                continue
            }
            if frame.contains(mouseLocation) {
                return true
            }
        }

        // AX succeeded but cursor is not in any menu item.
        return false
    }

    /// Returns the concrete application menu item frame at the given cursor
    /// location, matching the menu item hit-testing used by click-through.
    private func applicationMenuItemFrame(at mouseLocation: CGPoint) -> CGRect? {
        guard
            let frontApp = NSWorkspace.shared.menuBarOwningApplication,
            let axApp = AXHelpers.application(for: frontApp),
            let menuBar: UIElement = try? axApp.attribute(.menuBar)
        else {
            return nil
        }

        // Capture the frame during hit-testing to avoid a redundant AX read.
        for child in AXHelpers.children(for: menuBar) {
            guard let frame = AXHelpers.frame(for: child) else {
                continue
            }
            if frame.contains(mouseLocation) {
                return frame
            }
        }
        return nil
    }
}

// MARK: - EventMonitor Helpers

/// Helper protocol to enable group operations across event
/// monitoring types.
@MainActor
private protocol EventMonitorProtocol {
    func start()
    func stop()
    /// Checks validity and restarts if needed. Returns `true` if running after call.
    @discardableResult
    func ensureRunning() -> Bool
}

extension EventMonitor: EventMonitorProtocol {}

extension EventTap: EventMonitorProtocol {
    fileprivate func start() {
        enable()
    }

    fileprivate func stop() {
        disable()
    }

    @discardableResult
    fileprivate func ensureRunning() -> Bool {
        if ensureValid() {
            if !isEnabled {
                enable()
            }
            return true
        }
        return false
    }
}
