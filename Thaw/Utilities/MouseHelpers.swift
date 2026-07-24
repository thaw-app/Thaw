//
//  MouseHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// A namespace for mouse helper operations.
enum MouseHelpers {
    private static let diagLog = DiagLog(category: "MouseHelpers")
    private static let cursorLock = DispatchQueue(label: "MouseHelpers.cursorLock")
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    /// The `CGDisplayHideCursor`/`CGDisplayShowCursor` calls that this count
    /// mirrors are made *inside* the same critical section, so the count and
    /// the window server's hide state can never diverge through interleaving
    /// (a hide landing between another thread's decrement and its show call
    /// used to strand the cursor hidden until the watchdog fired).
    private static nonisolated(unsafe) var cursorHideCount = 0
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var autoShowWorkItem: DispatchWorkItem?
    /// Protected by `cursorLock`. Deadline of the currently scheduled
    /// watchdog, used to extend — never shorten — coverage when nested
    /// holders request a longer timeout than the first hide armed.
    private static nonisolated(unsafe) var autoShowDeadline: DispatchTime = .distantFuture
    /// Protected by `cursorLock`. Bumped whenever the watchdog is armed or
    /// cancelled. A fired work item that lost the race with its own
    /// cancellation (already executing, blocked on the lock) compares its
    /// captured generation and becomes a no-op instead of force-showing a
    /// cursor a newer holder legitimately hid.
    private static nonisolated(unsafe) var watchdogGeneration = 0
    private static let defaultWatchdogTimeout: DispatchTimeInterval = .seconds(1)

    private static func formattedTimeout(_ interval: DispatchTimeInterval) -> String {
        switch interval {
        case let .seconds(s):
            return "\(s)s"
        case let .milliseconds(ms):
            return String(format: "%.3fs", Double(ms) / 1000)
        case let .microseconds(us):
            return String(format: "%.6fs", Double(us) / 1_000_000)
        case let .nanoseconds(ns):
            return String(format: "%.9fs", Double(ns) / 1_000_000_000)
        case .never:
            return "never"
        @unknown default:
            return "unknown"
        }
    }

    /// Arms the watchdog, or extends it when the requested timeout reaches
    /// past the currently scheduled deadline. Never shortens an armed
    /// watchdog: a nested short-timeout hide must not cut the safety window
    /// out from under an outer long-running holder (and vice versa, a
    /// nested long-timeout hide extends the 1s default a shorter first
    /// holder armed, so the watchdog can't force-show mid-operation).
    ///
    /// Must be called while holding `cursorLock`. Returns whether a new
    /// watchdog was scheduled so the caller can log outside the lock.
    private static func scheduleAutoShowLocked(after timeout: DispatchTimeInterval) -> Bool {
        let deadline = DispatchTime.now() + timeout
        if autoShowWorkItem != nil, autoShowDeadline >= deadline {
            return false
        }
        autoShowWorkItem?.cancel()
        watchdogGeneration += 1
        let generation = watchdogGeneration
        let workItem = DispatchWorkItem {
            forceShowCursor(reason: "watchdog timeout", generation: generation)
        }
        autoShowWorkItem = workItem
        autoShowDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
        return true
    }

    /// Must be called while holding `cursorLock`.
    private static func cancelAutoShowLocked() {
        autoShowWorkItem?.cancel()
        autoShowWorkItem = nil
        watchdogGeneration += 1
    }

    private static func forceShowCursor(reason: String, generation: Int) {
        var result = CGError.success
        var rearmed = false
        var isStale = false
        cursorLock.sync {
            guard generation == watchdogGeneration else {
                // This item was superseded or cancelled after it had already
                // started executing; the current cursor state belongs to a
                // newer holder.
                isStale = true
                return
            }
            cursorHideCount = 0
            autoShowWorkItem = nil
            result = CGDisplayShowCursor(CGMainDisplayID())
            if result != .success {
                // The safety net is the only recovery path once the count is
                // zero; keep it alive so a transiently failing show retries.
                rearmed = scheduleAutoShowLocked(after: defaultWatchdogTimeout)
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
    static func hideCursor(watchdogTimeout: DispatchTimeInterval? = nil) {
        let timeout = watchdogTimeout ?? defaultWatchdogTimeout
        var hideFailure: CGError?
        var scheduledWatchdog = false
        cursorLock.sync {
            cursorHideCount += 1
            if cursorHideCount == 1 {
                let result = CGDisplayHideCursor(CGMainDisplayID())
                guard result == .success else {
                    // Undo only this call's increment; a blanket reset to 0
                    // would wipe increments a concurrent holder still owns.
                    cursorHideCount -= 1
                    hideFailure = result
                    return
                }
            }
            scheduledWatchdog = scheduleAutoShowLocked(after: timeout)
        }
        if let hideFailure {
            diagLog.error("CGDisplayHideCursor failed with error code \(hideFailure.rawValue)")
        }
        if scheduledWatchdog {
            diagLog.debug("Cursor watchdog scheduled for \(formattedTimeout(timeout))")
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor
    /// if the count is `0`.
    static func showCursor() {
        var wasAlreadyZero = false
        var showFailure: CGError?
        cursorLock.sync {
            guard cursorHideCount > 0 else {
                wasAlreadyZero = true
                return
            }
            cursorHideCount -= 1
            guard cursorHideCount == 0 else { return }

            let result = CGDisplayShowCursor(CGMainDisplayID())
            if result == .success {
                cancelAutoShowLocked()
            } else {
                showFailure = result
                // The count is already zero, so no later showCursor call
                // will retry — keep the watchdog armed as the recovery path
                // instead of leaving the cursor stranded hidden.
                _ = scheduleAutoShowLocked(after: defaultWatchdogTimeout)
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
