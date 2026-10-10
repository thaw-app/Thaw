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

    /// Cursor hide/show bookkeeping. CGDisplayHideCursor/ShowCursor run inside the
    /// same critical section, so the count and the window server's hide state can't
    /// diverge (a hide between another thread's decrement and show stranded the cursor).
    private struct CursorState {
        var hideCount = 0
        /// The armed watchdog, if any. Sleeps until watchdogDeadline, then
        /// force-shows the cursor as the safety net against unbalanced hides.
        var watchdogTask: Task<Void, Never>?
        /// Deadline of the armed watchdog, so nested holders with a longer timeout
        /// extend coverage but never shorten it.
        var watchdogDeadline: ContinuousClock.Instant = .now
        /// Bumped on every arm or cancel. A fired watchdog that lost the race with its
        /// cancellation compares generations and no-ops instead of undoing a newer hide.
        var generation = 0
    }

    private static let cursorState = Mutex(CursorState())
    private static let defaultWatchdogTimeout: Duration = .seconds(1)

    /// Arms the watchdog, or extends it to a later deadline. Never shortens it: a
    /// nested short hide can't cut an outer holder's window, and a nested long hide
    /// extends a shorter first one.
    ///
    /// Call with the cursorState lock held. Returns whether a new watchdog was
    /// scheduled so the caller can log outside the lock.
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

    /// Must be called while holding the cursorState lock.
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
    /// space used by AppKit, with the origin at the bottom left
    /// of the screen.
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    /// Returns the location of the mouse cursor in the coordinate
    /// space used by CoreGraphics, with the origin at the top left
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
    /// if the count is 0.
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
                // The count is already zero, so no later showCursor will retry. Keep the
                // watchdog armed so the cursor isn't stranded hidden.
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
            // Posting mouseMoved is more reliable than warp while a menu tracks the cursor;
            // it updates the Window Server position even when warp is blocked.
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

    /// Returns the point to warp the cursor to in order to place it over a
    /// menu bar item, or nil if the item isn't on any of the given displays.
    ///
    /// CGWarpMouseCursorPosition clamps an offscreen point to the leftmost
    /// edge of a display, which sits under the Apple menu, so an item that is
    /// offscreen has to be left alone rather than warped to.
    ///
    /// - Parameters:
    ///   - bounds: The bounds of the item in global display coordinates.
    ///   - displayBounds: The bounds of the available displays in global
    ///     display coordinates.
    static func cursorPoint(overItemWithBounds bounds: CGRect, displayBounds: [CGRect]) -> CGPoint? {
        guard !bounds.isEmpty else {
            return nil
        }
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        guard displayBounds.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return point
    }

    /// Returns the cursor to `point` after an operation that moved it.
    ///
    /// An unconditional warp. The version that preferred the user's own position came
    /// with the macOS 27 backport (#811) and left with its revert (#857); it should
    /// return with #811.
    ///
    /// - Parameter point: The point to move the cursor to in global
    ///   display coordinates.
    static func restoreCursorPosition(to point: CGPoint) {
        warpCursor(to: point)
    }

    /// Returns a Boolean value that indicates whether a mouse button
    /// is pressed.
    ///
    /// - Parameter button: The mouse button to check. Pass nil to
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
    ///   movement event must have occurred in order to return true.
    static func lastMovementOccurred(
        within duration: Duration,
        stateID: CGEventSourceStateID = .combinedSessionState
    ) -> Bool {
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .mouseMoved)
        return .seconds(seconds) <= duration
    }

    /// Whether a physical press, release, or drag of any button happened within the
    /// interval. `isButtonPressed()` misses a click released before the check, so these
    /// timestamps are what make a bulk batch defer to a mid-sequence click.
    static func lastPointerButtonEventOccurred(
        within duration: Duration,
        stateID: CGEventSourceStateID = .combinedSessionState
    ) -> Bool {
        let eventTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        return eventTypes.contains { type in
            .seconds(CGEventSource.secondsSinceLastEventType(stateID, eventType: type)) <= duration
        }
    }

    /// Whether physical pointer input occurred after an operation took cursor
    /// ownership. HID-system timestamps exclude Thaw's synthetic warps/events.
    static func physicalPointerInputOccurred(
        since start: ContinuousClock.Instant,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        let elapsed = max(start.duration(to: now), .zero)
        return lastMovementOccurred(within: elapsed, stateID: .hidSystemState)
            || lastScrollWheelOccurred(within: elapsed, stateID: .hidSystemState)
            || lastPointerButtonEventOccurred(within: elapsed, stateID: .hidSystemState)
    }

    /// Pure cursor-ownership decision used by move and batch restoration.
    static func shouldRestoreSavedCursorPosition(
        physicalPointerInputOccurred: Bool
    ) -> Bool {
        !physicalPointerInputOccurred
    }

    /// Returns a Boolean value that indicates whether the last scroll
    /// wheel event occurred within the given duration.
    ///
    /// - Parameter duration: The duration within which the last scroll
    ///   wheel event must have occurred in order to return true.
    static func lastScrollWheelOccurred(
        within duration: Duration,
        stateID: CGEventSourceStateID = .combinedSessionState
    ) -> Bool {
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .scrollWheel)
        return .seconds(seconds) <= duration
    }
}
