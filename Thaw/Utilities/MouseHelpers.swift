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
            result = CGDisplayShowCursor(CGMainDisplayID())
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
            }
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
