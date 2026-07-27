//
//  MouseHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Synchronization

/// A namespace for mouse helper operations.
nonisolated enum MouseHelpers {
    private static let diagLog = DiagLog(category: "MouseHelpers")

    /// Cursor hide/show bookkeeping. The `CGDisplayHideCursor` /
    /// `CGDisplayShowCursor` calls that `hideCount` mirrors are made *inside*
    /// the same critical section, so the count and the window server's hide
    /// state can never diverge through interleaving (a hide landing between
    /// another thread's decrement and its show call used to strand the
    /// cursor hidden until the watchdog fired).
    private struct CursorState {
        var hideCount = 0
        /// Whether the hide is currently *suspended*: holders remain, but the
        /// cursor has been handed back to the user because they physically
        /// moved the mouse. The next `warpCursor` re-hides it.
        var isSuspended = false
        /// Whether the hide was suspended by user activity at any point in
        /// the current hide session (until `hideCount` returns to zero).
        /// Restore-position warps consult this: once the user has taken the
        /// pointer, yanking it back to where it was before the operation is
        /// the "cursor kidnapping" the hide exists to avoid.
        var wasSuspendedByUser = false
        /// Polls for hardware mouse movement while the cursor is hidden.
        var activityTask: Task<Void, Never>?
        /// Where the user last had the pointer while the hide was suspended.
        /// Restores warp here instead of to the pre-operation position, so a
        /// sequence that keeps warping the cursor to menu bar coordinates
        /// still leaves it where the user put it.
        var userPosition: CGPoint?
        /// When we last moved the cursor ourselves. Motion reported within
        /// `selfMotionGrace` of it is assumed to be our own warp echoing
        /// back rather than the user reaching for the mouse.
        var lastSelfMotion: ContinuousClock.Instant?
        /// The armed watchdog, if any. Sleeps until `watchdogDeadline`, then
        /// force-shows the cursor as the safety net against unbalanced hides.
        var watchdogTask: Task<Void, Never>?
        /// Deadline of the armed watchdog, used to extend — never shorten —
        /// coverage when nested holders request a longer timeout than the
        /// first hide armed.
        var watchdogDeadline: ContinuousClock.Instant = .now
        /// Bumped whenever the watchdog is armed or cancelled. A fired
        /// watchdog that lost the race with its own cancellation (already
        /// executing, blocked on the lock) compares its captured generation
        /// and becomes a no-op instead of force-showing a cursor a newer
        /// holder legitimately hid.
        var generation = 0
    }

    private static let cursorState = Mutex(CursorState())
    private static let defaultWatchdogTimeout: Duration = .seconds(1)

    /// How often the hidden cursor is checked against hardware mouse motion.
    private static let activityPollInterval: Duration = .milliseconds(80)
    /// Hardware motion at most this old counts as "the user is moving the
    /// mouse right now".
    private static let activityFreshness: TimeInterval = 0.15
    /// Motion reported this soon after one of our own warps is treated as
    /// the warp itself, not as the user. `CGWarpMouseCursorPosition` does not
    /// generate events, so this really only covers the fallback path that
    /// posts a synthetic `.mouseMoved`. Kept short deliberately: a window
    /// wider than the gap between consecutive warps would swallow the user's
    /// motion for the whole of a dense move sequence.
    private static let selfMotionGrace: Duration = .milliseconds(120)

    /// Arms the watchdog, or extends it when the requested timeout reaches
    /// past the currently scheduled deadline. Never shortens an armed
    /// watchdog: a nested short-timeout hide must not cut the safety window
    /// out from under an outer long-running holder (and vice versa, a
    /// nested long-timeout hide extends the 1s default a shorter first
    /// holder armed, so the watchdog can't force-show mid-operation).
    ///
    /// Must be called while holding the `cursorState` lock. Returns whether
    /// a new watchdog was scheduled so the caller can log outside the lock.
    private static func scheduleWatchdog(_ state: inout CursorState, after timeout: Duration) -> Bool {
        let deadline = ContinuousClock.now + timeout
        if state.watchdogTask != nil, state.watchdogDeadline >= deadline {
            return false
        }
        state.watchdogTask?.cancel()
        state.generation += 1
        let generation = state.generation
        state.watchdogTask = Task {
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            forceShowCursor(reason: "watchdog timeout", generation: generation)
        }
        state.watchdogDeadline = deadline
        return true
    }

    // MARK: User-activity suspension

    /// Starts the poller that hands the cursor back the moment the user
    /// physically moves the mouse.
    ///
    /// A balanced hide/show pair is not enough on its own: a menu bar item
    /// move can legitimately hold the cursor hidden for many seconds (retries,
    /// per-item settling, a whole profile apply), and an operation parked on
    /// an await holds it until the watchdog fires — up to 30 s. Either way the
    /// user reaches for the mouse and finds no pointer. Hardware motion is the
    /// signal that they want it back, so give it back immediately and let the
    /// next warp re-hide it.
    ///
    /// Must be called while holding the `cursorState` lock.
    private static func startActivityMonitor(_ state: inout CursorState) {
        state.activityTask?.cancel()
        state.activityTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: activityPollInterval)
                guard !Task.isCancelled else { return }
                recordUserPositionWhileSuspended()
                guard userIsMovingMouse() else { continue }
                suspendHideForUserActivity()
            }
        }
    }

    /// Must be called while holding the `cursorState` lock.
    private static func cancelActivityMonitor(_ state: inout CursorState) {
        state.activityTask?.cancel()
        state.activityTask = nil
        state.isSuspended = false
        state.wasSuspendedByUser = false
        state.lastSelfMotion = nil
    }

    /// Whether the *hardware* reported mouse motion just now.
    ///
    /// `hidSystemState` is deliberate: `combinedSessionState` also counts
    /// synthetic events, and the whole point is to distinguish the user's
    /// hand from our own event posting. The only `.mouseMoved` event this
    /// app ever posts is `warpCursor`'s fallback, which `selfMotionGrace`
    /// filters out.
    private static func userIsMovingMouse() -> Bool {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )
        return seconds >= 0 && seconds <= activityFreshness
    }

    /// Samples the pointer while it is on loan to the user. Only meaningful
    /// while the hide is suspended: at any other time the position is one we
    /// warped to ourselves.
    private static func recordUserPositionWhileSuspended() {
        let isSuspended = cursorState.withLock { state in
            state.isSuspended
        }
        guard isSuspended, let location = locationCoreGraphics else {
            return
        }
        cursorState.withLock { state in
            // Re-check: a warp may have resumed the hide in between.
            guard state.isSuspended else { return }
            state.userPosition = location
        }
    }

    /// Shows the cursor while keeping the hide count intact, so the holders
    /// stay balanced and the next warp can re-hide.
    private static func suspendHideForUserActivity() {
        var didSuspend = false
        var failure: CGError?
        let location = locationCoreGraphics
        cursorState.withLock { state in
            guard state.hideCount > 0, !state.isSuspended else {
                return
            }
            if let lastSelfMotion = state.lastSelfMotion,
               ContinuousClock.now - lastSelfMotion < selfMotionGrace
            {
                return
            }
            let result = CGDisplayShowCursor(CGMainDisplayID())
            guard result == .success else {
                failure = result
                return
            }
            state.isSuspended = true
            state.wasSuspendedByUser = true
            state.userPosition = location
            didSuspend = true
        }
        if let failure {
            diagLog.error("Cursor hide suspension failed with error code \(failure.rawValue)")
        } else if didSuspend {
            diagLog.info("Cursor handed back to the user (hardware mouse movement while hidden)")
        }
    }

    /// Re-applies a suspended hide. Must be called while holding the
    /// `cursorState` lock. Returns whether the cursor was re-hidden.
    private static func resumeHideIfSuspended(_ state: inout CursorState) -> Bool {
        guard state.hideCount > 0, state.isSuspended else {
            return false
        }
        guard CGDisplayHideCursor(CGMainDisplayID()) == .success else {
            return false
        }
        state.isSuspended = false
        return true
    }

    /// Must be called while holding the `cursorState` lock.
    private static func cancelWatchdog(_ state: inout CursorState) {
        state.watchdogTask?.cancel()
        state.watchdogTask = nil
        state.generation += 1
    }

    private static func forceShowCursor(reason: String, generation: Int) {
        var result = CGError.success
        var rearmed = false
        var isStale = false
        cursorState.withLock { state in
            guard generation == state.generation else {
                // This watchdog was superseded or cancelled after it had
                // already started executing; the current cursor state
                // belongs to a newer holder.
                isStale = true
                return
            }
            state.hideCount = 0
            state.watchdogTask = nil
            // A suspended hide has already shown the cursor; showing again
            // would drive the window server's own hide count negative.
            let alreadyVisible = state.isSuspended
            cancelActivityMonitor(&state)
            result = alreadyVisible ? .success : CGDisplayShowCursor(CGMainDisplayID())
            if result != .success {
                // The safety net is the only recovery path once the count is
                // zero; keep it alive so a transiently failing show retries.
                rearmed = scheduleWatchdog(&state, after: defaultWatchdogTimeout)
            }
        }
        if isStale {
            diagLog.debug("Stale cursor watchdog fired (reason: \(reason)), ignoring")
        } else if result != .success {
            diagLog.error("Force show cursor failed (reason: \(reason), error: \(result.rawValue), rearmed: \(rearmed))")
        } else {
            diagLog.info("Cursor force-shown (reason: \(reason))")
        }
    }

    /// Returns the location of the mouse cursor in the coordinate
    /// space used by `AppKit`, with the origin at the bottom left
    /// of the screen.
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    /// Returns the location of the mouse cursor in the coordinate
    /// space used by `CoreGraphics`, with the origin at the top left
    /// of the screen.
    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Hides the mouse cursor and increments the hide cursor count.
    static func hideCursor(watchdogTimeout: Duration? = nil) {
        let timeout = watchdogTimeout ?? defaultWatchdogTimeout
        var hideFailure: CGError?
        var scheduledWatchdog = false
        cursorState.withLock { state in
            state.hideCount += 1
            if state.hideCount == 1 {
                let result = CGDisplayHideCursor(CGMainDisplayID())
                guard result == .success else {
                    // Undo only this call's increment; a blanket reset to 0
                    // would wipe increments a concurrent holder still owns.
                    state.hideCount -= 1
                    hideFailure = result
                    return
                }
                startActivityMonitor(&state)
            }
            // A nested hide does not take a loaned-out pointer back on its
            // own: only an actual cursor move (`warpCursor`) needs it hidden
            // again, and that re-hides for itself.
            scheduledWatchdog = scheduleWatchdog(&state, after: timeout)
        }
        if let hideFailure {
            diagLog.error("CGDisplayHideCursor failed with error code \(hideFailure.rawValue)")
        }
        if scheduledWatchdog {
            diagLog.debug("Cursor watchdog scheduled for \(timeout)")
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor
    /// if the count is `0`.
    static func showCursor() {
        var wasAlreadyZero = false
        var showFailure: CGError?
        cursorState.withLock { state in
            guard state.hideCount > 0 else {
                wasAlreadyZero = true
                return
            }
            state.hideCount -= 1
            guard state.hideCount == 0 else { return }

            // A suspended hide already handed the cursor back; the session is
            // over, so just tear down its bookkeeping.
            if state.isSuspended {
                cancelActivityMonitor(&state)
                cancelWatchdog(&state)
                return
            }
            cancelActivityMonitor(&state)

            let result = CGDisplayShowCursor(CGMainDisplayID())
            if result == .success {
                cancelWatchdog(&state)
            } else {
                showFailure = result
                // The count is already zero, so no later showCursor call
                // will retry — keep the watchdog armed as the recovery path
                // instead of leaving the cursor stranded hidden.
                _ = scheduleWatchdog(&state, after: defaultWatchdogTimeout)
            }
        }

        if wasAlreadyZero {
            diagLog.debug("showCursor called with count already zero")
        } else if let showFailure {
            diagLog.error("CGDisplayShowCursor failed with error code \(showFailure.rawValue), watchdog kept armed")
        }
    }

    /// Moves the mouse cursor to the given point without generating
    /// events.
    ///
    /// - Parameter point: The point to move the cursor to in global
    ///   display coordinates.
    static func warpCursor(to point: CGPoint) {
        // Stamp the motion before it happens, and take the pointer back if it
        // was loaned to the user: a warp that lands while the cursor is
        // visible is exactly the "kidnapping" the hide exists to prevent.
        var resumed = false
        cursorState.withLock { state in
            state.lastSelfMotion = .now
            resumed = resumeHideIfSuspended(&state)
        }
        if resumed {
            diagLog.debug("Cursor re-hidden for warp after user-activity suspension")
        }
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            diagLog.warning("CGWarpMouseCursorPosition failed (error: \(result.rawValue)), falling back to CGEvent mouseMoved")
            // Posting a mouseMoved event is more reliable than warp when a
            // menu is tracking the cursor — the event updates the cursor
            // position in the Window Server even if warp is blocked.
            guard
                let source = CGEventSource(stateID: .hidSystemState),
                let event = CGEvent(
                    mouseEventSource: source,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: point,
                    mouseButton: .left
                )
            else {
                diagLog.error("Failed to create fallback mouseMoved event")
                return
            }
            event.post(tap: .cghidEventTap)
        }
    }

    /// Warps the cursor back to a position captured before the current hide,
    /// or to where the user left it if they took the pointer over in the
    /// meantime.
    ///
    /// Restoring to `point` is only correct while the pointer is still ours.
    /// Once the user has physically moved the mouse — which suspends the hide
    /// and makes the cursor visible again — warping back to where it sat
    /// before the operation is a visible yank away from where they just put
    /// it. Their own last position wins instead; the pre-operation one is
    /// stale by then.
    ///
    /// - Parameter point: The point to warp to, in global display
    ///   coordinates.
    static func restoreCursorPosition(to point: CGPoint) {
        let userPosition = cursorState.withLock { state in
            state.wasSuspendedByUser ? state.userPosition : nil
        }
        if let userPosition {
            diagLog.debug("Restoring cursor to the user's own position; they moved the mouse during the operation")
            warpCursor(to: userPosition)
        } else {
            warpCursor(to: point)
        }
    }

    /// Connects or disconnects the positions of the mouse and cursor.
    ///
    /// - Parameter connected: A Boolean value that determines whether
    ///   to connect or disconnect the positions.
    static func associateMouseAndCursor(_ connected: Bool) {
        let result = CGAssociateMouseAndMouseCursorPosition(connected ? 1 : 0)
        if result != .success {
            diagLog.error("CGAssociateMouseAndMouseCursorPosition failed with error code \(result.rawValue)")
        }
    }

    /// Returns a Boolean value that indicates whether a mouse button
    /// is pressed.
    ///
    /// - Parameter button: The mouse button to check. Pass `nil` to
    ///   check all available mouse buttons (Quartz supports up to 32).
    static func isButtonPressed(_ button: CGMouseButton? = nil) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        if let button {
            return CGEventSource.buttonState(stateID, button: button)
        }
        for n: UInt32 in 0 ... 31 {
            guard
                let button = CGMouseButton(rawValue: n),
                CGEventSource.buttonState(stateID, button: button)
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the last mouse
    /// movement event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last mouse
    ///   movement event must have occurred in order to return `true`.
    static func lastMovementOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .mouseMoved)
        return .seconds(seconds) <= duration
    }

    /// Returns a Boolean value that indicates whether the last scroll
    /// wheel event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last scroll
    ///   wheel event must have occurred in order to return `true`.
    static func lastScrollWheelOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .scrollWheel)
        return .seconds(seconds) <= duration
    }
}
