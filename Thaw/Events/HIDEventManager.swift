//
//  HIDEventManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import Combine
import MenuBarModel
import os
import ThawCapture

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

    /// Temporarily releases the macOS 27 visibility assertion while the system
    /// Clock's Notification Center panel is open.
    private var clockActivationTask: Task<Void, Never>?
    private var clockActivationTaskToken: UUID?
    private var clockMouseUpPending = false
    private var clockActivationDidPressClock = false
    private var clockClickBounds: CGRect?
    private var clockActivationCancelledByDrag = false

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

    /// Fallback teardown when the paired mouse-up never arrives.
    private var showOnClickGuardDeferredDisarmTask: Task<Void, Never>?

    /// Tracks the state of the swallow/disarm lifecycle for the click guard tap.
    nonisolated enum GuardMouseUpState {
        /// No mouse-down has been swallowed; guard tap is idle between clicks.
        case idle
        /// A mouse-down was swallowed; swallow the matching mouse-up but keep
        /// the guard armed afterward (double-click window still open).
        case swallowing
        /// A mouse-down was swallowed and teardown is pending; swallow the
        /// matching mouse-up then fully disarm the guard.
        case swallowingThenDisarm
    }

    /// The input driving a `GuardMouseUpState` transition. Each case
    /// corresponds to one of the state-changing call sites around the guard
    /// tap and its arm/expire/disarm helpers.
    nonisolated enum GuardMouseUpSignal {
        /// A `leftMouseUp` arrived while the guard tap was armed.
        case mouseUp
        /// A `leftMouseDown` landed in the guard region and should be
        /// swallowed while keeping the guard armed for the following
        /// mouse-up.
        case swallow
        /// A `leftMouseDown` landed in the guard region and completed an
        /// action (double-click reveal, option-click toggle) that also
        /// requires disarming the guard once the matching mouse-up is
        /// swallowed.
        case swallowThenDisarm
        /// The guard's deadline expired, or the guard is being torn down,
        /// while a mouse button may still be held; disarming must be
        /// deferred until the pending mouse-up is swallowed.
        case disarmRequested
    }

    /// Computes the next `GuardMouseUpState` for the show-on-click guard
    /// tap's swallow-then-disarm lifecycle. Pure function of the current
    /// state and the triggering signal — holds no reference to the tap,
    /// timers, or AppState, so the swallow/disarm contract can be
    /// characterized without a live CGEventTap or real mouse-up event.
    static nonisolated func nextGuardState(
        from current: GuardMouseUpState,
        given signal: GuardMouseUpSignal
    ) -> GuardMouseUpState {
        switch signal {
        case .mouseUp:
            return .idle
        case .swallow:
            return .swallowing
        case .swallowThenDisarm:
            return .swallowingThenDisarm
        case .disarmRequested:
            return current == .idle ? .idle : .swallowingThenDisarm
        }
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

    /// The ID of the display that last had the active menu bar.
    private var lastActiveMenuBarDisplayID: CGDirectDisplayID?

    /// The pending tooltip show task.
    private var tooltipTask: Task<Void, any Error>?

    /// The pending secondary-context-menu reveal task. Holding a reference lets
    /// a subsequent click (right or left) cancel the pre-100ms-delay reveal so
    /// the menu doesn't pop up after the user has already dismissed or moved on.
    private var pendingSecondaryContextMenuTask: Task<Void, any Error>?

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
                lastActiveMenuBarDisplayID = nil
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
        // Fall back to the active-menu-bar screen when the mouse screen cannot
        // be determined.
        // Note: getMenuBarHeight() is NOT used as a gate here because it may
        // return nil transiently during startup (before the Window Server has
        // populated the menu bar window list). The downstream hit-testing in
        // isMouseInsideMenuBar() / isMouseInsideEmptyMenuBarSpace() handles the
        // case where the menu bar is genuinely absent (fullscreen app, etc.).
        let screen: NSScreen
        if let s = NSScreen.screenWithMouse ?? NSScreen.main {
            screen = s
        } else if let s = bestScreen(appState: appState) {
            screen = s
        } else {
            return event
        }
        // Cancel any pending secondary-context-menu task on every mouse-down so
        // a dismiss click or a follow-up click can't be raced by a previously
        // scheduled reveal that hasn't yet cleared its 100ms delay.
        pendingSecondaryContextMenuTask?.cancel()
        switch event.type {
        case .leftMouseDown:
            let clickLocation = NSEvent.mouseLocation
            if
                event.modifierFlags.contains(.control),
                handleControlItemContextMenu(
                    appState: appState,
                    clickLocation: clickLocation
                )
            {
                break
            }
            // Check app menu first - if click is on app menu area, don't trigger
            // show-on-click or smart rehide (the click belongs to the app menu)
            let isAppMenuClick = handleApplicationMenuClickThrough(appState: appState, screen: screen)
            if !isAppMenuClick {
                handleShowOnClick(appState: appState, screen: screen, clickLocation: clickLocation, modifierFlags: event.modifierFlags, isDoubleClick: event.clickCount > 1)
                handleSmartRehide(with: event, appState: appState, screen: screen)
            }
        case .rightMouseDown:
            let clickLocation = NSEvent.mouseLocation
            if !handleControlItemContextMenu(
                appState: appState,
                clickLocation: clickLocation
            ) {
                handleSecondaryContextMenu(appState: appState, screen: screen)
            }
        default:
            return event
        }
        handlePreventShowOnHover(
            with: event,
            appState: appState,
            screen: screen
        )
        dismissMenuBarTooltip()

        // update control item states when active menu bar display changes
        let currentMenuBarID = NSScreen.screenWithActiveMenuBar?.displayID
        if currentMenuBarID != lastActiveMenuBarDisplayID {
            lastActiveMenuBarDisplayID = currentMenuBarID
            appState.menuBarManager.updateControlItemStates()
        }

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

            // also re-evaluate when active menu bar display changes
            let currentMenuBarID = NSScreen.screenWithActiveMenuBar?.displayID
            if currentMenuBarID != lastActiveMenuBarDisplayID {
                lastActiveMenuBarDisplayID = currentMenuBarID
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
            // Only swallow the mouse-up if it lands inside the guard region.
            // A session-wide swallow deletes mouse-ups meant for other menu bar
            // items (e.g. the Clock), preventing their menus from opening.
            guard isPointInsideShowOnClickGuardRegion(NSEvent.mouseLocation) else {
                guardMouseUpState = .idle
                return event
            }
            let priorState = guardMouseUpState
            guardMouseUpState = Self.nextGuardState(from: priorState, given: .mouseUp)
            if priorState == .swallowingThenDisarm {
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
            guardMouseUpState = Self.nextGuardState(from: guardMouseUpState, given: .swallowThenDisarm)
        } else if event.flags.contains(.maskAlternate),
                  appState.settings.advanced.useOptionClickToShowAlwaysHiddenSection,
                  let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                  alwaysHiddenSection.isEnabled
        {
            alwaysHiddenSection.toggle()
            guardMouseUpState = Self.nextGuardState(from: guardMouseUpState, given: .swallowThenDisarm)
        } else {
            guardMouseUpState = Self.nextGuardState(from: guardMouseUpState, given: .swallow)
        }

        return nil
    }

    /// Active tap that replaces a Clock click while an assessment restriction
    /// is held. The native click cannot open Notification Center in that state,
    /// so the tap consumes the physical pair and replays the activation after
    /// the section controller has temporarily released only the assertion.
    private(set) lazy var clockActivationTap = EventTap(
        label: "clockActivationTap",
        types: [.leftMouseDown, .leftMouseUp, .leftMouseDragged],
        location: .sessionEventTap,
        placement: .headInsertEventTap,
        option: .defaultTap
    ) { [weak self] _, event in
        guard let self else { return event }

        // If the tap disappeared after swallowing a Clock mouse-down, its
        // matching mouse-up may never reach us. Do not let that stale state
        // consume the next unrelated click's mouse-up.
        if event.type == .leftMouseDown,
           clockMouseUpPending,
           clockActivationTask == nil
        {
            Self.diagLog.warning("Clock activation bridge discarded a stale pending mouse-up")
            clockMouseUpPending = false
            clockClickBounds = nil
            clockActivationCancelledByDrag = false
        }

        if event.type == .leftMouseDragged, clockMouseUpPending {
            if let clockClickBounds,
               !clockClickBounds.insetBy(dx: -4, dy: -4).contains(event.location)
            {
                clockActivationCancelledByDrag = true
            }
            return nil
        }

        if event.type == .leftMouseUp, clockMouseUpPending {
            if let clockClickBounds,
               !clockClickBounds.insetBy(dx: -4, dy: -4).contains(event.location)
            {
                clockActivationCancelledByDrag = true
            }
            clockMouseUpPending = false
            return nil
        }

        // Preserve a balanced event pair if the user holds or repeats the
        // physical click before the replacement AX press. Once Clock has been
        // pressed, later clicks pass through so the user can close the panel.
        if event.type == .leftMouseDown,
           clockMouseUpPending || (clockActivationTask != nil && !clockActivationDidPressClock),
           let appState,
           Self.systemClockItem(
               at: event.location,
               in: appState.itemManager.lastOnScreenMenuBarItems.0 + appState.itemManager.itemCache.managedItems
           ) != nil
        {
            clockMouseUpPending = true
            return nil
        }

        guard event.type == .leftMouseDown,
              isEnabled,
              clockActivationTask == nil,
              let appState,
              let controller = appState.menuBarManager.sectionController,
              controller.shouldBridgeClockActivation
        else {
            return event
        }

        let recentItems = appState.itemManager.lastOnScreenMenuBarItems.0
        let cachedItems = appState.itemManager.itemCache.managedItems
        // Both item sets are snapshots, so a Clock that was concealed a moment
        // ago still carries the bounds and `isOnScreen` it had while visible.
        // Whatever now occupies that strip — Thaw's own chevron, most often —
        // would then be read as a Clock click and open Notification Center.
        // A Clock assigned to a hidden section has no visible hit region, so no
        // click can legitimately be one; only a Visible Clock can be bridged.
        guard let clickedClock = Self.systemClockItem(at: event.location, in: recentItems + cachedItems),
              controller.section(for: clickedClock) == .visible,
              controller.beginClockActivationBridge()
        else {
            return event
        }

        clockMouseUpPending = true
        clockActivationDidPressClock = false
        clockClickBounds = clickedClock.bounds
        clockActivationCancelledByDrag = false
        let displayID = Self.displayID(
            containing: clickedClock.bounds.center,
            fallback: appState.itemManager.itemCache.displayID
        )
        let token = UUID()
        clockActivationTaskToken = token
        clockActivationTask = Task { @MainActor [weak self, controller] in
            defer {
                controller.endClockActivationBridge()
                if self?.clockActivationTaskToken == token {
                    self?.clockActivationTask = nil
                    self?.clockActivationTaskToken = nil
                    self?.clockActivationDidPressClock = false
                    self?.clockClickBounds = nil
                    self?.clockActivationCancelledByDrag = false
                }
            }
            guard let self else { return }
            await performClockActivationBridge(displayID: displayID)
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
        clockActivationTap.start()
        configureCancellables()
    }

    /// Whether the mouse-moved event tap should be active based on current settings.
    private func needsMouseMovedTap(appState: AppState) -> Bool {
        appState.settings.general.showOnHover ||
            appState.settings.advanced.showMenuBarTooltips ||
            appState.settings.displaySettings.isAlwaysShowEnabledOnAnyDisplay
    }

    /// Returns whether hover handling may proceed for the current section
    /// state. The permission latch suppresses a new reveal after an explicit
    /// click/hotkey action, but must not suppress conceal-on-leave; hiding the
    /// section is what resets that latch for the next hover cycle.
    static nonisolated func shouldProcessHover(
        showOnHover: Bool,
        showOnHoverAllowed: Bool,
        sectionIsHidden: Bool
    ) -> Bool {
        showOnHover && (!sectionIsHidden || showOnHoverAllowed)
    }

    /// Maximum width a normal menu bar item can have. Windows wider than
    /// this are expanded section-divider control items used to push hidden
    /// items off-screen and must be excluded from the bounds lookup.
    static nonisolated let maxReasonableItemWidth: CGFloat = 500

    /// Maximum menu-bar mid-Y for bounds included in show-on / tooltip
    /// hit-testing. macOS 27 concealed items can retain phantom AX frames
    /// far below the menu bar; exclude those from empty-space detection.
    static nonisolated let maxMenuBarItemMidY: CGFloat = MenuBarItemGeometry.maxOnBarMidY

    /// Returns whether `location` lies inside any cached menu bar item bounds
    /// entry. On macOS 27, synthetic status-item window IDs have no live CG
    /// window, so cached AX bounds are trusted directly.
    static nonisolated func menuBarBoundsLookupContains(
        _ location: CGPoint,
        entries: [(windowID: CGWindowID, bounds: CGRect)],
        trustCachedBoundsWithoutLiveWindowVerification: Bool,
        liveWindowBounds: (CGWindowID) -> CGRect? = { Bridging.getWindowBounds(for: $0) }
    ) -> Bool {
        for entry in entries {
            guard entry.bounds.contains(location) else { continue }
            if trustCachedBoundsWithoutLiveWindowVerification {
                return true
            }
            if let currentBounds = liveWindowBounds(entry.windowID),
               currentBounds.contains(location)
            {
                return true
            }
        }
        return false
    }

    /// Finds the system Clock at a Core Graphics click location. Requiring both
    /// the anchored-system classification and Clock's assessment identifier
    /// avoids intercepting a third-party item that happens to be titled Clock.
    static nonisolated func systemClockItem(
        at location: CGPoint,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        items.first { item in
            item.isOnScreen
                && !item.bounds.isEmpty
                && item.bounds.contains(location)
                && isSystemClockItem(item)
        }
    }

    static nonisolated func isSystemClockItem(_ item: MenuBarItem) -> Bool {
        item.isNonConcealableSystemItem
            && SystemMenuBarModuleCatalog.assessmentSystemItemID(forTitle: item.tag.title) == 2
    }

    static func displayID(
        containing point: CGPoint,
        fallback: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        NSScreen.screens.first { CGDisplayBounds($0.displayID).contains(point) }?.displayID ?? fallback
    }

    /// Returns whether an item's bounds should participate in show-on-click,
    /// show-on-hover, show-on-scroll, and tooltip hit-testing.
    static nonisolated func shouldIncludeItemInMenuBarBoundsLookup(
        _ item: MenuBarItem,
        section: MenuBarSection.Name?
    ) -> Bool {
        guard item.bounds.width > 0, item.bounds.width <= maxReasonableItemWidth else {
            return false
        }
        guard item.bounds.midY <= maxMenuBarItemMidY else {
            return false
        }
        if #available(macOS 27, *), item.tag.isNativeOverflowPlaceholder {
            return false
        }
        guard let section else {
            return true
        }
        if section != .visible, !item.isNonConcealableSystemItem {
            return false
        }
        return true
    }

    static nonisolated func menuBarItemBoundsLookupEntries(
        from items: [MenuBarItem],
        excluding knownWindowIDs: Set<CGWindowID>,
        shouldInclude: (MenuBarItem) -> Bool
    ) -> [(windowID: CGWindowID, bounds: CGRect)] {
        var seenWindowIDs = knownWindowIDs
        var entries = [(windowID: CGWindowID, bounds: CGRect)]()

        for item in items where item.isOnScreen && !seenWindowIDs.contains(item.windowID) {
            guard shouldInclude(item) else {
                continue
            }

            entries.append((windowID: item.windowID, bounds: item.bounds))
            seenWindowIDs.insert(item.windowID)
        }

        return entries
    }

    /// Rebuilds the window bounds lookup table from the current item cache.
    ///
    /// Includes ALL menu bar item windows (both managed and unmanaged) so that
    /// clicks on unmanaged items like Clock and Control Center are correctly
    /// detected as being on a menu bar item, not on empty space.
    func refreshMenuBarItemBoundsLookup() {
        guard let appState else { return }
        rebuildWindowBoundsLookup(
            from: appState.itemManager.itemCache,
            including: appState.itemManager.lastOnScreenMenuBarItems.0
        )
    }

    /// Whether an item's cached bounds should participate in hover/click/tooltip
    /// hit-testing. On macOS 27, concealed and reflow-collateral items keep
    /// phantom AX frames (sometimes at y≈1400+) with no rendered glyph.
    private func shouldIncludeInMenuBarBoundsLookup(_ item: MenuBarItem) -> Bool {
        let section = appState?.menuBarManager.sectionController?.section(for: item)
        return Self.shouldIncludeItemInMenuBarBoundsLookup(item, section: section)
    }

    /// Rebuilds the window bounds lookup table from the current item cache.
    ///
    /// Includes ALL menu bar item windows (both managed and unmanaged) so that
    /// clicks on unmanaged items like Clock and Control Center are correctly
    /// detected as being on a menu bar item, not on empty space.
    private func rebuildWindowBoundsLookup(
        from cache: MenuBarItemManager.ItemCache,
        including recentOnScreenItems: [MenuBarItem] = []
    ) {
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

        let recentEntries = Self.menuBarItemBoundsLookupEntries(
            from: recentOnScreenItems,
            excluding: knownWindowIDs,
            shouldInclude: shouldIncludeInMenuBarBoundsLookup
        )
        buffer.append(contentsOf: recentEntries)
        knownWindowIDs.formUnion(recentEntries.map(\.windowID))

        let managedEntries = Self.menuBarItemBoundsLookupEntries(
            from: cache.managedItems,
            excluding: knownWindowIDs,
            shouldInclude: shouldIncludeInMenuBarBoundsLookup
        )
        buffer.append(contentsOf: managedEntries)
        let entries = buffer
        windowBoundsLock.withLock { $0 = entries }
    }

    /// Rebuilds the bounds lookup using the current on-screen menu bar layout.
    ///
    /// Section show/hide changes often keep the same window IDs while moving
    /// items on or off screen. Rebuilding from the last item cache in those
    /// moments can leave hit testing with stale geometry, so use a direct
    /// Window Server snapshot instead.
    ///
    /// On macOS 27, status items no longer have individual CG windows, so the
    /// Window Server snapshot is empty and would wipe AX-derived bounds. Rebuild
    /// from the item cache instead so show-on-click stays constrained to truly
    /// empty menu bar space.
    private func rebuildWindowBoundsLookupFromCurrentLayout() {
        if #available(macOS 27, *) {
            guard let appState else {
                windowBoundsLock.withLock { $0 = [] }
                return
            }
            rebuildWindowBoundsLookup(
                from: appState.itemManager.itemCache,
                including: appState.itemManager.lastOnScreenMenuBarItems.0
            )
            return
        }

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
            // Pre-seed so the initial CombineLatest3 emission is treated as a
            // no-op when showOnHover is already true at subscription time,
            // avoiding unnecessary startup rearm work.
            lastShowOnHover = appState.settings.general.showOnHover

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
                    self?.rebuildWindowBoundsLookup(
                        from: cache,
                        including: appState.itemManager.lastOnScreenMenuBarItems.0
                    )
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
            rebuildWindowBoundsLookup(
                from: appState.itemManager.itemCache,
                including: appState.itemManager.lastOnScreenMenuBarItems.0
            )
        }

        // Periodically check that the mouseMovedTap is still alive.
        // macOS can invalidate the Mach port under resource pressure or
        // when accessibility permissions change. If it becomes invalid,
        // ensureValid() will recreate it.
        // Interval matches the stuck-disable recovery threshold so a leaked
        // stopAll is noticed within ~10s (not one 30s tick later).
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performHealthCheck()
            }
        }
        healthCheckTimer?.tolerance = 2
    }

    /// Checks the health of event monitors and taps, and attempts
    /// recovery if needed.
    private func performHealthCheck() {
        // Detect a stuck disabled state. If disableCount > 0 and we've
        // been disabled for longer than any legitimate operation would
        // take (e.g. a move or click), the count is likely imbalanced
        // due to a cancelled Task or unexpected error. Force recovery.
        if !isEnabled, disableCount > 1, let lastStop = lastStopTimestamp {
            let elapsed = ContinuousClock.now - lastStop
            // Nested stopAll (count>1) held past the settle window is almost
            // certainly a leaked pause (IamWJC log: stuck 37s at disableCount=2).
            // A single in-flight move (count==1) is left alone.
            if elapsed > .seconds(10) {
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

        // Keep this tap alive while ordinary HID monitors are paused by a
        // synthetic click/move. It may still owe the system a swallowed mouse-up
        // from the physical Clock click that started the bridge.
        if clockActivationTap.ensureValid(), !clockActivationTap.isEnabled {
            clockActivationTap.start()
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

    isolated deinit {
        healthCheckTimer?.invalidate()
        clockActivationTask?.cancel()
    }
}

// MARK: - Handler Methods

extension HIDEventManager {
    private func performClockActivationBridge(displayID: CGDirectDisplayID?) async {
        // Do not synthesize the replacement activation while the physical mouse
        // button is still down; Clock can otherwise immediately dismiss it on
        // the swallowed mouse-up.
        guard await waitForClockMouseUp() else {
            Self.diagLog.warning("Clock activation bridge timed out waiting for mouse-up")
            return
        }
        guard !clockActivationCancelledByDrag else {
            Self.diagLog.info("Clock activation bridge cancelled by drag")
            return
        }

        guard await pressSystemClock(displayID: displayID) else {
            Self.diagLog.error("Clock activation bridge AX press failed")
            return
        }
        clockActivationDidPressClock = true
        Self.diagLog.info("Clock activation bridge pressed Clock; waiting for Notification Center")

        var panelWindowIDs = Set<CGWindowID>()
        for _ in 0 ..< 20 {
            guard !Task.isCancelled else { return }
            panelWindowIDs = notificationCenterPanelWindowIDs()
            if !panelWindowIDs.isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !panelWindowIDs.isEmpty else {
            Self.diagLog.warning("Clock activation bridge did not observe Notification Center")
            return
        }

        // Match Lounge's bounded menu-dismiss wait: keep the assertion released
        // while the panel is visible, but never strand it after an observation
        // failure or a panel that remains open indefinitely.
        var closedSamples = 0
        for _ in 0 ..< 300 {
            guard !Task.isCancelled else { return }
            panelWindowIDs = notificationCenterPanelWindowIDs()
            if panelWindowIDs.isEmpty {
                closedSamples += 1
                if closedSamples >= 3 {
                    return
                }
            } else {
                closedSamples = 0
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        Self.diagLog.warning("Clock activation bridge reached its 30s safety timeout")
    }

    private func pressSystemClock(displayID: CGDirectDisplayID?) async -> Bool {
        guard #available(macOS 27, *) else { return false }

        for _ in 0 ..< 10 {
            guard !Task.isCancelled, !clockActivationCancelledByDrag else { return false }
            if MenuBarItemAXProvider.pressSystemClock(on: displayID) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func waitForClockMouseUp() async -> Bool {
        for _ in 0 ..< 100 {
            guard !Task.isCancelled else { return false }
            if !clockMouseUpPending {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return !clockMouseUpPending
    }

    private func notificationCenterPanelWindowIDs() -> Set<CGWindowID> {
        let pids = Set(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).map(\.processIdentifier)
        )
        guard !pids.isEmpty else { return [] }
        let displayBounds = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        return Set(WindowInfo.createWindows(option: .onScreen).compactMap { window in
            guard pids.contains(window.ownerPID),
                  window.isOnScreen,
                  Self.matchesDisplayBounds(window.bounds, displays: displayBounds)
            else {
                return nil
            }
            return window.windowID
        })
    }

    static nonisolated func matchesDisplayBounds(
        _ windowBounds: CGRect,
        displays displayBounds: [CGRect],
        tolerance: CGFloat = 2
    ) -> Bool {
        displayBounds.contains { display in
            abs(display.minX - windowBounds.minX) <= tolerance
                && abs(display.minY - windowBounds.minY) <= tolerance
                && abs(display.width - windowBounds.width) <= tolerance
                && abs(display.height - windowBounds.height) <= tolerance
        }
    }

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

    private func handleShowOnClick(appState: AppState, screen: NSScreen, clickLocation: CGPoint, modifierFlags: NSEvent.ModifierFlags, isDoubleClick: Bool = false) {
        guard appState.settings.general.showOnClick else {
            return
        }

        // Suppress show-on-click when no menu bar status items are currently
        // rendered on-screen for the active space. This catches the case where
        // a fullscreen app has auto-hidden the menu bar and the click lands in
        // the top-of-screen trigger zone before the menu bar visually reveals.
        // NSApp.currentSystemPresentationOptions is per-app and does not
        // reflect another app's fullscreen state, so the items-list signal is
        // used directly without a precondition.
        if !screen.isSystemMenuBarVisible() {
            Self.diagLog.debug("handleShowOnClick: suppressing, no menu bar items on-screen for active space")
            return
        }

        guard isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) else {
            return
        }

        // Defer to third-party menu bar widgets such as notch overlay
        // applications whose windows aren't reported in the standard menu bar
        // items query but visually occupy menu bar space. The AX hit-test
        // resolves the actual UI element at the cursor, so clicks that land
        // on a widget's icon don't also trigger Thaw's show-on-click reveal.
        if isCursorOverForeignWidgetUIElement() {
            Self.diagLog.debug("handleShowOnClick: suppressing, cursor over foreign UI element")
            return
        }

        if isDoubleClick {
            guard appState.settings.general.showOnDoubleClick else {
                return
            }
            Task {
                if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                   alwaysHiddenSection.isEnabled
                {
                    alwaysHiddenSection.toggle()
                }
            }
        } else {
            if modifierFlags.contains(.control) {
                handleSecondaryContextMenu(appState: appState, screen: screen)
                return
            }

            if modifierFlags.contains(.option) {
                if appState.settings.advanced.useOptionClickToShowAlwaysHiddenSection,
                   let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                   alwaysHiddenSection.isEnabled
                {
                    Task { alwaysHiddenSection.toggle() }
                }
                return
            }

            if let hiddenSection = appState.menuBarManager.section(withName: .hidden),
               hiddenSection.isEnabled
            {
                // If the always-hidden section is currently showing via the Thaw
                // Bar, a plain click should close it rather than switch the Thaw
                // Bar to the hidden section.
                if appState.menuBarManager.iceBarPanel.currentSection == .alwaysHidden,
                   let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
                {
                    disarmShowOnClickGuard()
                    Task { alwaysHiddenSection.hide() }
                    return
                }

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

        // Validate (and recreate if needed) before enabling; a stale Mach port
        // would silently no-op on start() and leave the guard tap inactive.
        guard showOnClickGuardTap.ensureValid() else {
            disarmShowOnClickGuard()
            return
        }
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
        let deferredState = Self.nextGuardState(from: guardMouseUpState, given: .disarmRequested)
        if deferredState != .idle {
            // Mouse button is still held; defer full teardown until the
            // swallowed mouse-up arrives so the tap stays active.
            guardMouseUpState = deferredState
            showOnClickGuardDeadline = nil
            showOnClickGuardRegion = nil
            showOnClickGuardDisplayID = nil
            clickTask = nil
            clickTaskToken = nil
            scheduleDeferredShowOnClickGuardDisarm()
            return
        }

        disarmShowOnClickGuard()
    }

    private func disarmShowOnClickGuard() {
        // If we're waiting for a swallowed mouse-up, defer disarming until it arrives.
        // This keeps the CGEventTap active until the swallowed mouse-up is processed
        // and prevents a stray mouse-up being delivered to the system.
        let deferredState = Self.nextGuardState(from: guardMouseUpState, given: .disarmRequested)
        if deferredState != .idle {
            guardMouseUpState = deferredState
            scheduleDeferredShowOnClickGuardDisarm()
            return
        }

        clickTask?.cancel()
        clickTask = nil
        clickTaskToken = nil
        showOnClickGuardDeferredDisarmTask?.cancel()
        showOnClickGuardDeferredDisarmTask = nil
        showOnClickGuardDeadline = nil
        showOnClickGuardRegion = nil
        showOnClickGuardDisplayID = nil
        guardMouseUpState = .idle
        showOnClickGuardTap.stop()
    }

    private func scheduleDeferredShowOnClickGuardDisarm() {
        showOnClickGuardDeferredDisarmTask?.cancel()
        showOnClickGuardDeferredDisarmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                guard self?.guardMouseUpState == .swallowingThenDisarm else { return }
                self?.showOnClickGuardDeferredDisarmTask = nil
                self?.guardMouseUpState = .idle
                self?.disarmShowOnClickGuard()
            }
        }
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

    /// Pure decision for the show-on-click guard tap: whether a click at
    /// `clickLocation` should be swallowed rather than passed through to the
    /// system. Holds no reference to `NSScreen`, the event tap, or AppState
    /// so the region/double-click-window contract can be characterized
    /// without a live CGEventTap.
    ///
    /// `isDoubleClick` does not currently gate this decision — the first
    /// swallowed mouse-down in the region is not yet known to be part of a
    /// double click, and the guard tap only inspects `clickState` after this
    /// predicate has already returned `true`. It is threaded through so a
    /// future contract that does need to distinguish the double-click case
    /// from the initial swallow has somewhere to hook in without changing
    /// this function's signature.
    static nonisolated func shouldSwallowClick(
        clickLocation: CGPoint,
        guardRegion: CGRect,
        isDoubleClick _: Bool,
        withinDoubleClickWindow: Bool
    ) -> Bool {
        guard withinDoubleClickWindow else {
            return false
        }
        return guardRegion.contains(clickLocation)
    }

    private func isPointInsideShowOnClickGuardRegion(_ point: CGPoint) -> Bool {
        expireShowOnClickGuardIfNeeded()
        guard let region = showOnClickGuardRegion,
              let displayID = showOnClickGuardDisplayID
        else {
            return false
        }

        guard NSScreen.screenWithMouse?.displayID == displayID else {
            return false
        }

        return Self.shouldSwallowClick(
            clickLocation: point,
            guardRegion: region,
            isDoubleClick: false,
            withinDoubleClickWindow: isShowOnClickGuardActive
        )
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

        let rehideInterval = appState.settings.general.rehideInterval
        Task {
            // Respect the configured rehide interval before closing after a
            // click outside the revealed section. The follow-up checks below
            // still verify focus/menu state at the time the hide would occur.
            do {
                try await Task.sleep(for: .seconds(rehideInterval))
            } catch {
                return
            }

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

    /// Returns whether macOS 27 should route a secondary click to the Thaw
    /// control item's menu instead of the empty-menu-bar context menu.
    static nonisolated func shouldShowControlItemContextMenu(
        usesMenuBarAgent: Bool,
        controlItemFrame: CGRect?,
        clickLocation: CGPoint
    ) -> Bool {
        usesMenuBarAgent && controlItemFrame?.contains(clickLocation) == true
    }

    /// Shows the menu belonging to the Thaw icon when the click lands inside
    /// its live frame. Returns whether the click was consumed by this route.
    private func handleControlItemContextMenu(
        appState: AppState,
        clickLocation: CGPoint
    ) -> Bool {
        guard #available(macOS 27, *) else {
            return false
        }
        guard let controlItem = appState.menuBarManager.section(withName: .visible)?.controlItem else {
            return false
        }
        let candidateFrame = controlItem.window?.frame
            ?? controlItem.frame
            ?? controlItem.onScreenFrame
        guard
            Self.shouldShowControlItemContextMenu(
                usesMenuBarAgent: true,
                controlItemFrame: candidateFrame,
                clickLocation: clickLocation
            )
        else {
            return false
        }

        Task {
            controlItem.showContextMenu(at: clickLocation)
        }
        return true
    }

    private func handleSecondaryContextMenu(
        appState: AppState,
        screen: NSScreen
    ) {
        pendingSecondaryContextMenuTask = Task { [weak self] in
            guard let self else { return }
            // Suppress when no menu bar items are rendered on-screen for the
            // active space. Catches phantom right-clicks landing in the menu bar
            // y-band while a fullscreen app has auto-hidden the menu bar; the
            // event still passes through to the underlying app so its native
            // context menu can appear normally.
            if !screen.isSystemMenuBarVisible() {
                Self.diagLog.debug("handleSecondaryContextMenu: suppressing, no menu bar items on-screen for active space")
                return
            }
            guard appState.settings.advanced.enableSecondaryContextMenu else {
                return
            }
            guard
                isMouseInsideEmptyMenuBarSpace(
                    appState: appState,
                    screen: screen
                )
            else {
                return
            }
            guard let mouseLocation = MouseHelpers.locationAppKit else {
                return
            }
            // Delay prevents the menu from immediately closing and gives any
            // foreign widget's own right-click menu a chance to render. Notch
            // overlay applications cover wide regions of the menu bar visually
            // but only respond to clicks on their actual icon, so probing
            // whether a foreign menu opened in response to this click is more
            // accurate than testing window bounds.
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            if isForeignPopUpMenuOpen() {
                Self.diagLog.debug("handleSecondaryContextMenu: suppressing, foreign pop-up menu is open")
                return
            }
            if isCursorOverForeignWidgetUIElement() {
                Self.diagLog.debug("handleSecondaryContextMenu: suppressing, cursor over foreign UI element")
                return
            }
            appState.menuBarManager.showSecondaryContextMenu(at: mouseLocation)
        }
    }

    /// Returns whether the cursor sits on a UI element owned by a foreign
    /// third-party menu bar widget such as a notch overlay application,
    /// using the system-wide accessibility hit-test. Excludes Thaw's own
    /// elements, the Window Server (which owns the menu bar background), and
    /// elements with a menu-bar / menu / menu-item role (the front app's
    /// File/Edit/View region returns the app's PID but a menu-bar-class
    /// role). When the helper returns true, Thaw defers to the widget under
    /// the cursor even if the widget didn't open its own pop-up menu in
    /// response to the click.
    private func isCursorOverForeignWidgetUIElement() -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        guard let element = AXHelpers.element(at: mouseLocation) else {
            return false
        }
        guard let pid = AXHelpers.pid(for: element), pid > 0 else {
            return false
        }
        if pid == getpid() {
            return false
        }
        // SystemUIServer owns part of the system menu bar; AX returning it
        // indicates the cursor is over empty menu bar space. WindowServer also
        // renders menu bar surfaces but is a system daemon with no bundle
        // identifier, so NSRunningApplication can't resolve it; fall back to a
        // process-name lookup via proc_name for that case. On macOS 27+,
        // MenuBarAgent took over rendering the menu bar and appears here instead.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if bundleID == "com.apple.systemuiserver" {
            return false
        }
        // macOS 27+: MenuBarAgent renders the menu bar; treat it like SystemUIServer.
        if #available(macOS 27, *), bundleID == "com.apple.MenuBarAgent" {
            return false
        }
        if isWindowServerPID(pid) {
            return false
        }
        // The frontmost application owns its own menu bar background between
        // File/Edit/View items. AX returns the app's menu bar element here
        // even though the geometric isMouseInsideEmptyMenuBarSpace check
        // already passed (no specific menu item is hit). Filter by role: a
        // menu bar / menu / menu item role means the cursor is over the front
        // app's menu bar, not over a third-party widget overlay.
        return !AXHelpers.isMenuBarChromeRole(element)
    }

    /// Returns whether the given PID belongs to the macOS WindowServer
    /// daemon. WindowServer has no bundle identifier and is not represented as
    /// an NSRunningApplication, so the executable name has to be read via
    /// proc_name. Used to exclude WindowServer-owned AX elements from the
    /// foreign-widget hit-test.
    private func isWindowServerPID(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return proc_name(pid, base, UInt32(ptr.count))
        }
        guard length > 0 else { return false }
        let procName = buffer.prefix { $0 != 0 }.map(UInt8.init)
        return String(data: Data(procName), encoding: .utf8) == "WindowServer"
    }

    /// Returns whether any non-Thaw window at the pop-up-menu window level is
    /// currently on-screen. Right-click menus (NSMenu and equivalents) render
    /// at kCGPopUpMenuWindowLevel, while persistent overlay windows from
    /// notch overlay applications sit a level below. Filtering to the exact
    /// pop-up level distinguishes an actually open menu from a widget's idle
    /// overlay, which is needed to avoid showing Thaw's secondary context
    /// menu after a click that landed on a foreign widget that opened its own
    /// menu.
    private func isForeignPopUpMenuOpen() -> Bool {
        let ownPID = getpid()
        let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = WindowInfo.createWindows(option: .onScreen)
        for window in windows where window.ownerPID != ownPID {
            guard window.layer == popUpLevel else { continue }
            return true
        }
        return false
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
            isMouseInsideMenuBarItem(appState: appState, screen: screen)
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
        // Only continue if we have a hidden section (we should).
        guard
            let hiddenSection = appState.menuBarManager.section(
                withName: .hidden
            )
        else {
            return
        }

        guard Self.shouldProcessHover(
            showOnHover: appState.settings.general.showOnHover,
            showOnHoverAllowed: appState.menuBarManager.showOnHoverAllowed,
            sectionIsHidden: hiddenSection.isHidden
        ) else {
            return
        }

        let delay = appState.settings.advanced.showOnHoverDelay

        if hiddenSection.isHidden {
            guard
                isMouseInsideEmptyMenuBarSpace(
                    appState: appState,
                    screen: screen
                ),
                !isCursorOverForeignWidgetUIElement()
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
                !isMouseInsideMenuBarHoverBand(appState: appState, screen: screen),
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
            // If the user turned off auto-rehide entirely, don't schedule a
            // hover-triggered hide — leave the section open until an explicit
            // close action (click, hotkey, etc.).
            guard appState.settings.general.autoRehide else {
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
            // Respect the user's configured rehide interval, not the short
            // show-hover delay. Using showOnHoverDelay (0.2 s) here caused the
            // section to collapse before the user could interact with any item.
            let hideDelay = appState.settings.general.rehideInterval
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
                try await Task.sleep(for: .seconds(hideDelay))
                // Make sure the manager is still enabled and the mouse is still
                // outside. Use the hover-retention band rather than the precise
                // menu bar edge so cursor tremor at the boundary does not let
                // the in-flight hide survive `rehideInterval` and re-trigger the
                // show→hide→show loop.
                guard
                    isEnabled,
                    appState.settings.general.autoRehide,
                    !isMouseInsideMenuBarHoverBand(appState: appState, screen: screen),
                    !isMouseInsideIceBar(appState: appState)
                else {
                    return
                }
                // Don't hide while the user is interacting with an open menu.
                if await appState.itemManager.isAnyMenuBarItemMenuOpen() {
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
            !appState.menuBarManager.shouldUseIceBar(for: screen.displayID)
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
            !isCursorOverForeignWidgetUIElement(),
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
        guard ScreenCapture.hasCachedScreenRecordingPermission else {
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

    /// Returns `true` when the cursor is inside the menu bar or within the
    /// small ``MenuBarTuning/hoverRetentionPadding`` band kept just below it.
    ///
    /// Used only by the hide arm of show-on-hover and by the section rehide
    /// active-area check, so cursor micro-tremor at the menu bar edge of an
    /// inline (non-Thaw Bar) reveal does not schedule a hide that survives
    /// `rehideInterval` and restarts the show→hide→show loop. The show arm
    /// and click/scroll paths keep using the precise ``isMouseInsideMenuBar``
    /// so user intent is still honoured for show-on-click and scroll.
    func isMouseInsideMenuBarHoverBand(appState _: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return false
        }

        let padding = Constants.MenuBarTuning.hoverRetentionPadding
        return mouseLocation.x >= screen.frame.minX
            && mouseLocation.x <= screen.frame.maxX
            && mouseLocation.y <= screen.frame.maxY
            && mouseLocation.y >= screen.frame.maxY - menuBarHeight - padding
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
        // Extend the frame left to the screen edge to cover the Apple menu.
        applicationMenuFrame.size.width +=
            applicationMenuFrame.origin.x - screen.frame.origin.x
        applicationMenuFrame.origin.x = screen.frame.origin.x
        // Cap the right edge at the notch so locations over the notch are not
        // counted as inside the application menu.
        if let notch = screen.frameOfNotch {
            let cappedMaxX = min(applicationMenuFrame.maxX, notch.minX)
            applicationMenuFrame.size.width = cappedMaxX - applicationMenuFrame.origin.x
        }
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// Returns `true` when the current mouse location hits a cached menu bar item
    /// bounds entry. This is the fast path used by hover/click hit testing.
    private func isMouseInsideCachedMenuBarItem() -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }

        let entries = windowBoundsLock.withLock { $0 }
        let trustCachedBounds = if #available(macOS 27, *) {
            true
        } else {
            false
        }
        return Self.menuBarBoundsLookupContains(
            mouseLocation,
            entries: entries,
            trustCachedBoundsWithoutLiveWindowVerification: trustCachedBounds
        )
    }

    /// macOS 27 fallback when the bounds lookup table is empty or stale.
    private func isMouseInsideManagedItemBounds(
        appState: AppState,
        at mouseLocation: CGPoint
    ) -> Bool {
        guard #available(macOS 27, *) else {
            return false
        }

        let controller = appState.menuBarManager.sectionController
        return appState.itemManager.itemCache.managedItems.contains { item in
            guard item.bounds.contains(mouseLocation) else {
                return false
            }
            let section = controller?.section(for: item)
            return Self.shouldIncludeItemInMenuBarBoundsLookup(item, section: section)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    func isMouseInsideMenuBarItem(appState: AppState, screen _: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }

        // Use the pre-built bounds lookup table, which is rebuilt
        // whenever the item cache changes. This avoids per-event
        // IPC calls to the Window Server.
        if isMouseInsideCachedMenuBarItem() {
            return true
        }

        if isMouseInsideManagedItemBounds(appState: appState, at: mouseLocation) {
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
    ///
    /// This is the single shared guard for every show-on entry point —
    /// `handleShowOnClick`, `handleShowOnHover`, and `handleShowOnScroll` —
    /// so a status item missed by hit-testing here would let all three fire
    /// on top of it. Item presence is decided by ``isMouseInsideMenuBarItem``,
    /// which on macOS 27 trusts AX-derived bounds (see
    /// ``menuBarBoundsLookupContains``) and falls back to the managed-items
    /// cache when the lookup is empty.
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
        //
        // Status items (Clock, Control Center, third-party icons, …) are excluded via
        // `isMouseInsideMenuBarItem`, which on macOS 27 uses AX-derived bounds because
        // individual CG windows no longer exist.
        let appMenuResult = isMouseInsideApplicationMenuClickRegion(
            appState: appState,
            screen: screen
        )

        // Use the AX result when available; fall back to geometric detection
        // when hit-testing is indeterminate (e.g., due to expanded section-divider
        // windows interfering with AX queries).
        let isInAppMenu: Bool = if let result = appMenuResult {
            result
        } else {
            isMouseInsideApplicationMenu(appState: appState, screen: screen)
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
            // Use the live window frame instead of the debounced controlItem.frame.
            // controlItem.frame has a 50ms debounce and can be stale immediately
            // after the context menu closes, causing hit-testing to incorrectly
            // classify an icon click as empty-space and double-fire show/toggle.
            let iceIconFrame = visibleSection.controlItem.window?.frame,
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
