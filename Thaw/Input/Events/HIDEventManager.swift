//
//  HIDEventManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import MenuBarModel
import os
import ThawCapture

/// Watches the pointer and the keyboard modifiers, and drives every behaviour
/// the menu bar exposes through them: revealing hidden items on a click, a
/// hover, or a scroll, rehiding them again, dragging items around, and putting
/// up tooltips and context menus.
///
/// The manager owns a handful of EventMonitors and EventTaps. They are all
/// installed and torn down together through startAll() and stopAll(),
/// which nest, so overlapping callers cannot switch each other off.
@MainActor
@Observable
final class HIDEventManager {
    static nonisolated let diagLog = DiagLog(category: "HIDEventManager")

    /// Whether a command-drag of a menu bar item is in progress.
    var isDraggingMenuBarItem = false

    /// The app-wide state this manager reads settings and sections from.
    /// Weak, because the app state owns the manager.
    weak var appState: AppState?

    /// Captured at performSetup(with:); hover/click guards consult them
    /// directly rather than reaching through the item manager.
    var menuOpenMonitor: MenuOpenMonitor?
    var onScreenItems: OnScreenItemSnapshot?

    /// The Accessibility answers the taps read instead of querying AX inline.
    let pointerAXCache = MenuBarPointerAXCache()

    /// The settings this component reads. MenuBarEngineConfiguration states
    /// why the engine holds this rather than AppState.
    var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    /// Thread-safe counter for mouse-moved event throttling.
    private nonisolated let mouseMovedThrottleCounter = OSAllocatedUnfairLock(initialState: 0)

    /// Timestamp of the last forwarded app menu click, used to debounce
    /// duplicate events from a single physical interaction.
    var lastAppMenuClickTime: CFAbsoluteTime = 0

    /// Keeps the Combine subscriptions set up in configureCancellables() alive.
    var cancellables = Set<AnyCancellable>()

    /// Task observing GeneralSettings.showOnHover,
    /// AdvancedSettings.showMenuBarTooltips and
    /// DisplaySettingsManager.configurations, which are all @Observable.
    var hoverSettingsObservationTask: Task<Void, Never>?

    /// Timer that periodically checks whether the event tap is still
    /// valid and attempts to recreate it if the Mach port was invalidated.
    var healthCheckTimer: Timer?

    /// The currently pending show-on-hover delay task.
    var hoverTask: Task<Void, any Error>?

    /// Identity token for the current hover task so an older task cannot
    /// clear state that belongs to a newer one.
    var hoverTaskToken: UUID?

    /// A short-lived recovery task that repeatedly re-evaluates show-on-hover
    /// right after the setting is enabled, so the first hover does not depend
    /// on a later mouse-moved event or the periodic health check.
    var hoverRearmTask: Task<Void, Never>?
    var hoverRearmTaskToken: UUID?

    /// Tracks the last seen value of showOnHover so the hover-settings
    /// observation can restrict rearm logic to false→true transitions only.
    var lastShowOnHover: Bool?

    /// The currently pending hover action, used to avoid restarting the same
    /// delay window on every small mouse move inside the same region.
    var pendingHoverAction: HoverAction?

    /// Whether the section now out was revealed by hovering. A hover reveal
    /// hides again after hoverRevealHideDelay, not the rehide interval meant
    /// for click and hotkey reveals.
    var isHoverReveal = false

    /// The pending task that clears the temporary show-on-click guard.
    var clickTask: Task<Void, Never>?

    var notificationCenterInput = NotificationCenterInputState()
    var clockMenuBarBands: [CGRect] = []
    var notificationCenterHotkeys: [SystemNotificationCenterHotkey] = []

    @ObservationIgnored
    lazy var notificationCenterActivation = NotificationCenterActivation { [weak self] request in
        await self?.performNotificationCenterActivation(request)
    }

    /// Identity token for the current click task so a late/re-armed task
    /// cannot call expireShowOnClickGuard after it has been superseded.
    var clickTaskToken: UUID?

    /// The deadline for the temporary show-on-click protection region.
    var showOnClickGuardDeadline: ContinuousClock.Instant?

    /// The temporary protected region around the first click that revealed
    /// hidden items. Clicks inside this region are intercepted until the
    /// system double-click window expires.
    var showOnClickGuardRegion: CGRect?

    /// The display hosting the current protected region.
    var showOnClickGuardDisplayID: CGDirectDisplayID?

    /// Fallback teardown when the paired mouse-up never arrives.
    var showOnClickGuardDeferredDisarmTask: Task<Void, Never>?

    /// Identity token for the deferred disarm task so a superseded task cannot
    /// tear the guard down on behalf of its replacement.
    var showOnClickGuardDeferredDisarmToken: UUID?

    /// The first click in empty menu bar space, waiting out the double-click
    /// window so a second click can claim the always-hidden section instead.
    var pendingMenuBarClick: (timestamp: ContinuousClock.Instant, displayID: CGDirectDisplayID)?

    /// Performs the pending hidden-section reveal once the window closes.
    var pendingMenuBarClickTask: Task<Void, Never>?

    /// The pending smart-rehide task armed by a click outside the menu bar,
    /// tracked so a later reveal can cancel it before it hides the section the
    /// user just brought back.
    var smartRehideTask: Task<Void, Never>?

    var guardMouseUpState: GuardMouseUpState = .idle

    /// The number of times the manager has been told to stop.
    private var disableCount = 0

    /// Timestamp of the last stopAll() call, used by the health check
    /// to detect a stuck disabled state.
    private var lastStopTimestamp: ContinuousClock.Instant?

    /// Thread-safe lookup table mapping menu bar window IDs to their bounds.
    /// Rebuilt from itemCache whenever it changes, eliminating
    /// per-event Window Server IPC calls during mouse movement.
    ///
    /// The CGEventTap callback reads this on the main run loop and Combine
    /// writes it on the main thread. That guarantee is implicit, so a lock
    /// makes the safety explicit.
    nonisolated let windowBoundsLock = OSAllocatedUnfairLock(
        initialState: [(windowID: CGWindowID, bounds: CGRect)]()
    )

    /// The window ID of the menu bar item the mouse is currently hovering over,
    /// used to detect when the cursor moves to a different item.
    var tooltipHoveredWindowID: CGWindowID?

    /// The ID of the display the mouse was last seen on.
    private var lastMouseScreenID: CGDirectDisplayID?

    /// The ID of the display that last had the active menu bar.
    private var lastActiveMenuBarDisplayID: CGDirectDisplayID?

    /// When the active menu bar display was last asked of the window server.
    ///
    /// The pointer stream only needs to notice a display change promptly, not
    /// on every event, so it re-asks at most once per
    /// activeMenuBarCheckInterval. Clicks always ask, since a click is
    /// what moves the menu bar between displays in the first place.
    private var lastActiveMenuBarCheck: ContinuousClock.Instant?

    /// How long the pointer stream trusts the last active-menu-bar answer.
    private static let activeMenuBarCheckInterval: Duration = .milliseconds(100)

    /// The pending tooltip show task.
    var tooltipTask: Task<Void, any Error>?

    /// The pending secondary-context-menu reveal task. Holding a reference lets
    /// a subsequent click (right or left) cancel the pre-100ms-delay reveal so
    /// the menu doesn't pop up after the user has already dismissed or moved on.
    var pendingSecondaryContextMenuTask: Task<Void, any Error>?

    /// The control item whose menu a press requested but has not yet released.
    ///
    /// Raised on the release, not the press: the host hands us the press, and
    /// a menu opened during it is dismissed by the release that follows.
    var pendingControlItemContextMenu: (item: ControlItem, location: CGPoint)?

    /// The last visible-control-item rect that was actually on a screen.
    @ObservationIgnored
    var lastUsableVisibleControlItemBounds: CGRect?

    /// Whether the monitors are meant to be listening right now.
    ///
    /// Flipping this installs or removes all of them in one go; startAll()
    /// and stopAll() own the nesting that decides when it flips.
    private(set) var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else {
                return
            }
            guard isEnabled else {
                for monitor in allMonitors {
                    monitor.stop()
                }
                mouseMovedTap.stop()
                // A press that armed a control-item menu will never get its
                // release once the monitors are down; drop it.
                pendingControlItemContextMenu = nil
                // Forget which display the pointer was last on, so the next
                // enable recomputes it instead of trusting stale geometry.
                lastMouseScreenID = nil
                lastActiveMenuBarDisplayID = nil
                lastActiveMenuBarCheck = nil
                return
            }
            for monitor in allMonitors {
                monitor.start()
            }
            // The mouse-moved tap is the expensive one, so it only runs while
            // some setting actually wants a stream of pointer positions.
            if let appState, needsMouseMovedTap(appState: appState) {
                mouseMovedTap.start()
            }
        }
    }

    // MARK: Monitors

    /// Watches every left and right press, wherever it lands. Purely an
    /// observer, the press always continues on to whoever it was aimed at.
    @ObservationIgnored
    private(set) lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        self?.receiveMouseDown(event)
        return event
    }

    /// Everything the manager does in response to a press.
    private func receiveMouseDown(_ event: NSEvent) {
        if let cgEvent = event.cgEvent, NotificationCenterEventReplay.isReplay(cgEvent) {
            return
        }
        guard isEnabled, let appState else {
            return
        }
        // Prefer the screen the mouse is physically on so clicks on the external
        // monitor's menu bar are processed against the correct display geometry.
        // Fall back to the active-menu-bar screen when the mouse screen cannot
        // be determined.
        // getMenuBarHeight() is not used as a gate here because it may
        // return nil transiently during startup (before the Window Server has
        // populated the menu bar window list). The downstream hit-testing in
        // isMouseInsideMenuBar() / isMouseInsideEmptyMenuBarSpace() handles the
        // case where the menu bar is genuinely absent (fullscreen app, etc.).
        guard let screen = NSScreen.screenWithMouse ?? NSScreen.main ?? bestScreen(appState: appState) else {
            return
        }
        // Cancel any pending secondary-context-menu task on every mouse-down so
        // a dismiss click or a follow-up click can't be raced by a previously
        // scheduled reveal that hasn't yet cleared its 100ms delay.
        pendingSecondaryContextMenuTask?.cancel()

        switch event.type {
        case .leftMouseDown:
            receiveLeftMouseDown(event, appState: appState, screen: screen)
        case .rightMouseDown:
            receiveRightMouseDown(appState: appState, screen: screen)
        default:
            // Not a press we subscribed to; nothing below applies.
            return
        }

        handlePreventShowOnHover(
            with: event,
            appState: appState,
            screen: screen
        )
        dismissMenuBarTooltip()

        if activeMenuBarDisplayDidChange(rateLimited: false) {
            appState.menuBarManager.updateControlItemStates()
        }
    }

    /// Whether the active menu bar has moved to another display since the
    /// last time anyone looked, updating lastActiveMenuBarDisplayID.
    ///
    /// Each look is a round trip to the window server, and the pointer stream
    /// asks on every throttled move. A rateLimited caller therefore gets
    /// false without asking while the previous answer is younger than
    /// activeMenuBarCheckInterval; the menu bar does not hop between
    /// displays faster than that, and the stream will re-ask within the same
    /// window either way. The active display follows focus and clicks rather
    /// than any one notification, which is why this is rate-limited instead
    /// of cached against an invalidation set.
    private func activeMenuBarDisplayDidChange(rateLimited: Bool) -> Bool {
        let now = ContinuousClock.now
        if
            rateLimited,
            let lastActiveMenuBarCheck,
            now - lastActiveMenuBarCheck < Self.activeMenuBarCheckInterval
        {
            return false
        }
        lastActiveMenuBarCheck = now
        let currentMenuBarID = NSScreen.screenWithActiveMenuBar?.displayID
        guard currentMenuBarID != lastActiveMenuBarDisplayID else {
            return false
        }
        lastActiveMenuBarDisplayID = currentMenuBarID
        // The active bar moving posts no notification; the topology settles it with the rest.
        DisplayTopology.shared.noteActiveBarMayHaveMoved()
        return true
    }

    /// The left-press pipeline: control-item context menu, app menu
    /// click-through, then show-on-click and smart rehide.
    ///
    /// Returning early only skips the rest of this pipeline, the shared
    /// bookkeeping in receiveMouseDown(_:) still runs afterwards.
    private func receiveLeftMouseDown(_ event: NSEvent, appState: AppState, screen: NSScreen) {
        // A menu armed by an earlier press whose release never arrived must
        // not fire on this click's release.
        pendingControlItemContextMenu = nil
        recordControlItemPressModifiers(event, appState: appState)
        let clickLocation = NSEvent.mouseLocation
        if
            event.modifierFlags.contains(.control),
            armControlItemContextMenu(appState: appState, clickLocation: clickLocation)
        {
            return
        }
        // A click on the app menu area belongs to the app menu, so it must not
        // trigger show-on-click or smart rehide.
        guard !handleApplicationMenuClickThrough(appState: appState, screen: screen) else {
            return
        }
        handleShowOnClick(
            appState: appState,
            screen: screen,
            clickLocation: clickLocation,
            modifierFlags: event.modifierFlags
        )
        handleSmartRehide(with: event, appState: appState, screen: screen)
    }

    /// Records the Thaw icon's press-time modifiers, or clears a stale record
    /// for any other press: the forwarded activation lands after the mouse-up.
    private func recordControlItemPressModifiers(_ event: NSEvent, appState: AppState) {
        guard let controlItem = appState.menuBarManager.section(withName: .visible)?.controlItem else {
            return
        }
        guard event.modifierFlags.contains(.option) else {
            controlItem.recordPrimaryPressModifiers(nil)
            return
        }
        let clickLocation = NSEvent.mouseLocation
        controlItem.recordPrimaryPressModifiers(
            pressLandsOnControlItem(controlItem, appState: appState, clickLocation: clickLocation)
                ? event.modifierFlags
                : nil
        )
    }

    /// The right-press pipeline: the control item claims the press first, and
    /// only otherwise does the empty-space context menu get a chance.
    private func receiveRightMouseDown(appState: AppState, screen: NSScreen) {
        pendingControlItemContextMenu = nil
        let clickLocation = NSEvent.mouseLocation
        guard !armControlItemContextMenu(appState: appState, clickLocation: clickLocation) else {
            return
        }
        handleSecondaryContextMenu(appState: appState, screen: screen)
    }

    /// Watches for the left button coming back up, which ends any item drag and
    /// raises a control-item menu a control-click requested.
    @ObservationIgnored
    private(set) lazy var mouseUpMonitor = EventMonitor.universal(
        for: .leftMouseUp
    ) { [weak self] event in
        if let self, isEnabled {
            flushPendingControlItemContextMenu()
            handleMenuBarItemDragStop()
        }
        return event
    }

    /// Watches the right button coming back up, which is when a right-click on
    /// the Thaw icon raises its menu.
    @ObservationIgnored
    private(set) lazy var rightMouseUpMonitor = EventMonitor.universal(
        for: .rightMouseUp
    ) { [weak self] event in
        if let self, isEnabled {
            flushPendingControlItemContextMenu()
        }
        return event
    }

    /// Watches left-button drags, which may be the start of an item move.
    @ObservationIgnored
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

    /// Follows the pointer itself. This is a listen-only tap rather than an
    /// EventMonitor because mouse-moved events have to be seen even while
    /// another app is tracking the mouse.
    @ObservationIgnored
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

            if activeMenuBarDisplayDidChange(rateLimited: true) {
                appState.menuBarManager.updateControlItemStates(for: screen)
            }

            if isMouseInsideMenuBar(appState: appState, screen: screen),
               let mouseLocation = MouseHelpers.locationCoreGraphics
            {
                pointerAXCache.refreshForeignWidget(at: mouseLocation)
            }
            handleShowOnHover(appState: appState, screen: screen)
            handleMenuBarTooltip(appState: appState, screen: screen)
        }
        return event
    }

    /// Watches scroll gestures, which can reveal or hide the hidden section.
    @ObservationIgnored
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
    @ObservationIgnored
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
            let priorState = guardMouseUpState
            // A swallowed mouse-down always owns its matching mouse-up, and
            // expiry clears the region while the button is still held, so a
            // pending disarm has to swallow unconditionally. The region test
            // only applies while the guard is still merely swallowing: a
            // session-wide swallow would otherwise delete mouse-ups meant for
            // other menu bar items (e.g. the Clock) and stop their menus from
            // opening.
            let ownsMouseUp = priorState == .swallowingThenDisarm
                || isPointInsideShowOnClickGuardRegion(NSEvent.mouseLocation)
            guard ownsMouseUp else {
                guardMouseUpState = .idle
                return event
            }
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
        // Only click state 2 is the gesture; a higher state is the user still
        // clicking, not another double-click.
        if clickState == 2,
           configuration.showOnClick,
           let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
           alwaysHiddenSection.isEnabled
        {
            cancelSmartRehide()
            alwaysHiddenSection.show()
            guardMouseUpState = Self.nextGuardState(from: guardMouseUpState, given: .swallowThenDisarm)
        } else if event.flags.contains(.maskAlternate),
                  let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                  alwaysHiddenSection.isEnabled
        {
            cancelSmartRehide()
            alwaysHiddenSection.toggle()
            guardMouseUpState = Self.nextGuardState(from: guardMouseUpState, given: .swallowThenDisarm)
        } else {
            guardMouseUpState = Self.nextGuardState(from: guardMouseUpState, given: .swallow)
        }

        return nil
    }

    /// Active tap that replaces a Clock click while the kit's restriction
    /// is held. The native click cannot open Notification Center in that state,
    /// so the tap consumes the physical pair and replays the activation after
    /// the section controller has temporarily released only the assertion.
    @ObservationIgnored
    private(set) lazy var clockActivationTap = EventTap(
        label: "clockActivationTap",
        types: [.leftMouseDown, .leftMouseUp, .leftMouseDragged],
        location: .sessionEventTap,
        placement: .headInsertEventTap,
        option: .defaultTap
    ) { [weak self] _, event in
        guard let self else { return event }

        guard !NotificationCenterEventReplay.isReplay(event) else { return event }

        if event.type == .leftMouseDragged, notificationCenterInput.hasClockPress {
            notificationCenterInput.dragClockPress(to: event.location)
            return nil
        }
        if event.type == .leftMouseUp, notificationCenterInput.hasClockPress {
            if let point = notificationCenterInput.endClockPress(at: event.location) {
                enqueueNotificationCenterActivation(.clock(point))
            }
            return nil
        }
        guard event.type == .leftMouseDown else { return event }
        notificationCenterInput.discardClockPress()
        guard isEnabled, let appState else { return event }
        let controller = appState.menuBarManager.sectionController
        guard controller.shouldBridgeClockActivation || notificationCenterActivation.isBusy else { return event }
        // No AX walk, display query, or capture runs in this synchronous tap.
        guard let clock = Self.systemClockItem(
            at: event.location,
            in: (onScreenItems?.items ?? []) + appState.itemManager.managedItems,
            menuBarBands: clockMenuBarBands
        ), controller.section(for: clock) == .visible else { return event }
        notificationCenterInput.beginClockPress(at: event.location, bounds: clock.bounds)
        // Release at mouse-down so the completed click replays with no added settle.
        notificationCenterActivation.prepareLease(
            begin: {
                let cover = appState.menuBarManager.clockBridgeCover
                cover.show()
                guard controller.beginClockActivationBridge(scope: .global) else {
                    cover.hide(immediately: true)
                    return .unavailable
                }
                appState.itemManager.beginNotificationCenterLayoutSuspension()
                return .acquired
            },
            restore: {
                controller.endClockActivationBridge()
                appState.itemManager.endNotificationCenterLayoutSuspension()
                appState.menuBarManager.clockBridgeCover.hide()
            }
        )
        return nil
    }

    /// Watches the system's "Show Notification Center" keyboard shortcut.
    ///
    /// The held assertion suppresses that shortcut like a Clock click, so a
    /// matching press is swallowed, the assertion lifted, and the press replayed.
    @ObservationIgnored
    private(set) lazy var notificationCenterHotkeyTap = EventTap(
        label: "notificationCenterHotkeyTap",
        types: [.keyDown, .keyUp],
        location: .hidEventTap,
        placement: .headInsertEventTap,
        option: .defaultTap
    ) { [weak self] _, event in
        guard let self else { return event }
        return handleNotificationCenterHotkey(event)
    }

    // MARK: All Monitors

    /// The NSEvent-backed monitors, which are always started and stopped as
    /// a set. The event taps are handled separately, since each has its own
    /// condition for being live.
    @ObservationIgnored
    private lazy var allMonitors: [any EventMonitorProtocol] = [
        mouseDownMonitor,
        mouseUpMonitor,
        rightMouseUpMonitor,
        mouseDraggedMonitor,
        scrollWheelMonitor,
    ]

    // MARK: Setup

    /// Wires the manager to the app state and brings its monitors up. Call
    /// once, during app startup.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configuration = appState.settings
        menuOpenMonitor = appState.itemManager.menuOpenMonitor
        onScreenItems = appState.itemManager.onScreenItemSnapshot
        startAll()
        synchronizeClockActivationTap()
        synchronizeNotificationCenterHotkeyTap()
        configureCancellables()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.synchronizeNotificationCenterHotkeyTap()
                // The menu bar just changed hands; read the new owner's titles
                // now so the first click on them finds them cached.
                if let pid = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier {
                    self?.pointerAXCache.refreshApplicationMenu(for: pid)
                }
            }
            .store(in: &cancellables)
    }

    /// Whether the section controller could ever ask for a Clock click to be
    /// bridged.
    ///
    /// The tap that does the bridging is an active session-level tap on every
    /// left press, so it is only worth installing when a real section engine
    /// is behind the controller. The stand-in controller answers false for
    /// MenuBarSectionControlling.shouldBridgeClockActivation forever, so
    /// with it the tap would only ever pass events straight through. The
    /// engine's own answer still swings with the assertion state at runtime;
    /// that is decided per click inside the tap, because nothing in here can
    /// learn of an assertion being acquired quickly enough to bring the tap
    /// up before the click that needs it.
    private var canBridgeClockActivation: Bool {
        appState?.menuBarManager.sectionController.isOperational ?? false
    }

    /// Brings the Clock activation tap in line with whether bridging is
    /// possible at all: up when the section engine is real, down otherwise.
    ///
    /// Deliberately independent of isEnabled. The tap stays live across a
    /// stopAll() because it may still owe the system the mouse-up matching
    /// a physical Clock press it swallowed before the pause began.
    func synchronizeClockActivationTap() {
        if canBridgeClockActivation || notificationCenterInput.hasClockPress {
            if clockActivationTap.ensureValid(), !clockActivationTap.isEnabled {
                clockActivationTap.start()
            }
        } else if clockActivationTap.isEnabled {
            clockActivationTap.stop()
        }
    }

    /// Brings the notification-center hotkey tap in line with whether bridging
    /// is possible at all, mirroring synchronizeClockActivationTap().
    ///
    /// A disabled shortcut leaves the tap down. Otherwise it handles the
    /// configured chord, including the system's default Fn-N.
    func synchronizeNotificationCenterHotkeyTap() {
        let hotkeys = SystemNotificationCenterHotkey.shortcuts()
        if hotkeys != notificationCenterHotkeys {
            Self.diagLog.info("Notification Center shortcut bindings updated: \(hotkeys.count) enabled")
        }
        notificationCenterHotkeys = hotkeys
        if (canBridgeClockActivation && !hotkeys.isEmpty) || notificationCenterInput.hasHeldKeys {
            if notificationCenterHotkeyTap.ensureValid(), !notificationCenterHotkeyTap.isEnabled {
                notificationCenterHotkeyTap.start()
            }
        } else if notificationCenterHotkeyTap.isEnabled {
            notificationCenterHotkeyTap.stop()
        }
    }

    /// Whether the mouse-moved event tap should be active based on current settings.
    func needsMouseMovedTap(appState: AppState) -> Bool {
        configuration.showOnHover ||
            configuration.showMenuBarTooltips ||
            appState.settings.displaySettings.isAlwaysShowEnabledOnAnyDisplay
    }

    /// Checks the health of event monitors and taps, and attempts
    /// recovery if needed.
    func performHealthCheck() {
        // Detect a stuck disabled state. If disableCount > 0 and we've
        // been disabled for longer than any legitimate operation would
        // take (e.g. a move or click), the count is likely imbalanced
        // due to a cancelled Task or unexpected error. Force recovery.
        if !isEnabled, disableCount > 1, let lastStop = lastStopTimestamp {
            let elapsed = ContinuousClock.now - lastStop
            // Nested stopAll (count > 1) held past the settle window is almost
            // certainly a leaked pause. A single in-flight move (count == 1)
            // is left alone.
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
        // from the physical Clock click that started the bridge. The same
        // call takes it down again should the controller have stopped being
        // one that can bridge.
        synchronizeClockActivationTap()
        synchronizeNotificationCenterHotkeyTap()

        guard isEnabled else { return }

        // Restart any NSEvent monitors macOS silently invalidated, for example
        // after an accessibility permission change or under resource pressure.
        for monitor in allMonitors {
            monitor.ensureRunning()
        }

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

    /// Undoes one stopAll().
    ///
    /// Stops nest: the monitors only come back once every outstanding stop has
    /// been matched, so two callers suppressing the manager at the same time
    /// cannot re-enable it behind each other's backs.
    func startAll() {
        if disableCount > 0 {
            disableCount -= 1
        }
        if disableCount == 0 {
            isEnabled = true
            lastStopTimestamp = nil
        }
    }

    /// Suppresses the manager until a matching startAll() arrives, and
    /// abandons whatever hover, guard, or tooltip work was in flight.
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
        cancelPendingMenuBarClick()
        disarmShowOnClickGuard()
        dismissMenuBarTooltip()
    }

    isolated deinit {
        healthCheckTimer?.invalidate()
        notificationCenterActivation.cancel()
        hoverSettingsObservationTask?.cancel()
    }
}

// MARK: - EventMonitor Helpers

/// The little bit of vocabulary EventMonitor and EventTap have in common,
/// so that the manager can hold and drive a mixed collection of them.
@MainActor
protocol EventMonitorProtocol {
    func start()
    func stop()
    /// Checks validity and restarts if needed. Returns true if running after call.
    @discardableResult
    func ensureRunning() -> Bool
}

extension EventMonitor: EventMonitorProtocol {}

/// A tap speaks in terms of being enabled rather than started, and its Mach
/// port can be torn down by the system underneath it, so "still running" has
/// to mean both still valid and still switched on.
extension EventTap: EventMonitorProtocol {
    func start() {
        enable()
    }

    func stop() {
        disable()
    }

    @discardableResult
    func ensureRunning() -> Bool {
        guard ensureValid() else {
            return false
        }
        if !isEnabled {
            enable()
        }
        return true
    }
}
