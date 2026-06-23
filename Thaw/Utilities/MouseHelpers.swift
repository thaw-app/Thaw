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
    private static nonisolated(unsafe) var cursorHideCount = 0
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var cursorHideGeneration: UInt64 = 0
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var autoShowWorkItem: DispatchWorkItem?
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var autoShowDeadline: DispatchTime?
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var autoShowGeneration: UInt64?
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var nextAutoShowID: UInt64 = 0
    /// Protected by `cursorLock` — all accesses go through `cursorLock.sync`.
    private static nonisolated(unsafe) var autoShowID: UInt64?
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

    private static func scheduleAutoShow(after timeout: DispatchTimeInterval = defaultWatchdogTimeout, generation: UInt64) {
        if case .never = timeout {
            diagLog.debug("Cursor watchdog disabled")
            return
        }

        let deadline = DispatchTime.now() + timeout
        var shouldSchedule = false
        var workItem: DispatchWorkItem?
        cursorLock.sync {
            guard cursorHideCount > 0, cursorHideGeneration == generation else {
                return
            }

            if
                autoShowGeneration == generation,
                let autoShowDeadline,
                autoShowDeadline.uptimeNanoseconds <= deadline.uptimeNanoseconds
            {
                return
            }

            nextAutoShowID &+= 1
            let watchdogID = nextAutoShowID
            let nextWorkItem = DispatchWorkItem {
                forceShowCursor(reason: "watchdog timeout", generation: generation, watchdogID: watchdogID)
            }

            autoShowWorkItem?.cancel()
            autoShowWorkItem = nextWorkItem
            autoShowDeadline = deadline
            autoShowGeneration = generation
            autoShowID = watchdogID
            workItem = nextWorkItem
            shouldSchedule = true
        }

        guard shouldSchedule, let workItem else {
            return
        }

        diagLog.debug("Cursor watchdog scheduled for \(formattedTimeout(timeout))")
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
    }

    private static func cancelAutoShow(generation: UInt64) {
        cursorLock.sync {
            guard autoShowGeneration == generation else {
                return
            }

            autoShowWorkItem?.cancel()
            autoShowWorkItem = nil
            autoShowDeadline = nil
            autoShowGeneration = nil
            autoShowID = nil
        }
    }

    private static func forceShowCursor(reason: String, generation: UInt64, watchdogID: UInt64) {
        var shouldShow = false
        cursorLock.sync {
            guard
                cursorHideCount > 0,
                cursorHideGeneration == generation,
                autoShowGeneration == generation,
                autoShowID == watchdogID
            else {
                return
            }

            shouldShow = true
        }

        guard shouldShow else {
            diagLog.debug("Ignoring stale cursor force-show (reason: \(reason))")
            return
        }

        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            diagLog.error("Force show cursor failed (reason: \(reason), error: \(result.rawValue))")
            scheduleAutoShow(after: .milliseconds(250), generation: generation)
        } else {
            cursorLock.sync {
                guard cursorHideGeneration == generation else { return }
                cursorHideCount = 0
                autoShowWorkItem?.cancel()
                autoShowWorkItem = nil
                autoShowDeadline = nil
                autoShowGeneration = nil
                autoShowID = nil
            }
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
        var shouldHide = false
        var generation: UInt64 = 0
        cursorLock.sync {
            cursorHideCount += 1
            if cursorHideCount == 1 {
                cursorHideGeneration &+= 1
                shouldHide = true
            }
            generation = cursorHideGeneration
        }

        guard shouldHide else {
            scheduleAutoShow(after: watchdogTimeout ?? defaultWatchdogTimeout, generation: generation)
            return
        }

        let result = CGDisplayHideCursor(CGMainDisplayID())
        if result != .success {
            diagLog.error("CGDisplayHideCursor failed with error code \(result.rawValue)")
            cursorLock.sync {
                guard cursorHideGeneration == generation else {
                    return
                }

                cursorHideCount = 0 // Reset on failure
                autoShowWorkItem?.cancel()
                autoShowWorkItem = nil
                autoShowDeadline = nil
                autoShowGeneration = nil
                autoShowID = nil
            }
        } else {
            scheduleAutoShow(after: watchdogTimeout ?? defaultWatchdogTimeout, generation: generation)
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor
    /// if the count is `0`.
    static func showCursor() {
        var shouldShow = false
        var wasAlreadyZero = false
        var generation: UInt64 = 0
        cursorLock.sync {
            if cursorHideCount > 0 {
                generation = cursorHideGeneration
                if cursorHideCount == 1 {
                    shouldShow = true
                } else {
                    cursorHideCount -= 1
                }
            } else {
                wasAlreadyZero = true
            }
        }

        if wasAlreadyZero {
            diagLog.debug("showCursor called with count already zero")
            return
        }

        guard shouldShow else { return }

        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            diagLog.error("CGDisplayShowCursor failed with error code \(result.rawValue)")
            scheduleAutoShow(after: .milliseconds(250), generation: generation)
        } else {
            cursorLock.sync {
                guard cursorHideGeneration == generation, cursorHideCount > 0 else { return }
                cursorHideCount = 0
            }
            cancelAutoShow(generation: generation)
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
