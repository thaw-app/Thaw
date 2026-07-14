//
//  MouseHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import AppKit

/// A namespace for mouse helper operations.
enum MouseHelpers {
    private static let diagLog = DiagLog(category: "MouseHelpers")
    private static let disableCursorWarpKey = "MouseHelpers.DisableCursorWarp"
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

    private static func scheduleAutoShow(
        after timeout: DispatchTimeInterval = defaultWatchdogTimeout,
        generation: UInt64,
        allowShorten: Bool = false
    ) {
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

            // Keep the watchdog at the latest (longest) active deadline for this
            // generation. A nested hide with a shorter timeout (e.g. scrombleEvent's
            // default 1s nested inside a move's 2s hide) must not shrink the
            // watchdog, or it fires mid-operation and flashes the cursor visible at
            // the wrong location. Only extend the deadline, never shorten it.
            //
            // `allowShorten` is set by the show-failure fast-retry paths: when a
            // CGDisplayShowCursor call fails we want to retry showing in ~250ms
            // regardless of any longer hide watchdog still armed, so the cursor
            // doesn't stay hidden up to the outer window on a failed show.
            if
                !allowShorten,
                autoShowGeneration == generation,
                let autoShowDeadline,
                autoShowDeadline.uptimeNanoseconds >= deadline.uptimeNanoseconds
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

    /// Forces the WindowServer to re-render the cursor sprite after a
    /// hide/show cycle performed from the background.
    ///
    /// `CGDisplayShowCursor` rebalances the connection's hide count, but
    /// when the show comes from a background connection (Thaw sets
    /// `SetsCursorInBackground`) after the pointer was warped around by a
    /// synthetic drag, the sprite is not always repainted: the cursor
    /// stays invisible — clicks land correctly, nothing is drawn — until
    /// some app re-asserts a cursor image (hovering the Dock is the
    /// classic manual recovery). Physical mouse movement doesn't reliably
    /// recover it because the frontmost app only sets a new cursor when
    /// the pointer crosses a cursor rect. Posting a synthetic mouseMoved
    /// at the current position makes the app under the pointer reset its
    /// cursor rect immediately, which repaints the sprite.
    private static func reassertCursorAfterShow() {
        guard
            let position = locationCoreGraphics,
            let source = CGEventSource(stateID: .hidSystemState),
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: position,
                mouseButton: .left
            )
        else {
            diagLog.warning("reassertCursorAfterShow: failed to create mouseMoved event")
            return
        }
        event.post(tap: .cghidEventTap)
        diagLog.debug("Posted cursor-reassert mouseMoved at \(formattedPoint(position))")
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
            scheduleAutoShow(after: .milliseconds(250), generation: generation, allowShorten: true)
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
            reassertCursorAfterShow()
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

    private static func formattedPoint(_ point: CGPoint?) -> String {
        guard let point else { return "nil" }
        return String(format: "(%.1f, %.1f)", point.x, point.y)
    }

    private static func formattedRect(_ rect: CGRect) -> String {
        String(
            format: "(x: %.1f, y: %.1f, w: %.1f, h: %.1f)",
            rect.origin.x,
            rect.origin.y,
            rect.width,
            rect.height
        )
    }

    private static func screenSummary(for target: CGPoint) -> String {
        let activeDisplayID = Bridging.getActiveMenuBarDisplayID()
        return NSScreen.screens.map { screen in
            let frame = screen.frame
            let cgBounds = CGDisplayBounds(screen.displayID)
            return """
            id=\(screen.displayID)\
            active=\(screen.displayID == activeDisplayID)\
            frame=\(formattedRect(frame))\
            cgBounds=\(formattedRect(cgBounds))\
            frameContainsTarget=\(frame.contains(target))\
            cgContainsTarget=\(cgBounds.contains(target))
            """
        }
        .joined(separator: "; ")
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
            scheduleAutoShow(after: .milliseconds(250), generation: generation, allowShorten: true)
        } else {
            cursorLock.sync {
                guard cursorHideGeneration == generation, cursorHideCount > 0 else { return }
                cursorHideCount = 0
            }
            cancelAutoShow(generation: generation)
            reassertCursorAfterShow()
        }
    }

    /// Moves the mouse cursor to the given point without generating
    /// events.
    ///
    /// - Parameter point: The point to move the cursor to in global
    ///   display coordinates.
    static func warpCursor(to point: CGPoint, reason: String = "unspecified") {
        let beforeCG = locationCoreGraphics
        let beforeAppKit = locationAppKit
        let screenWithMouse = NSScreen.screenWithMouse?.displayID
        let activeDisplayID = Bridging.getActiveMenuBarDisplayID()
        let disableCursorWarp = UserDefaults.standard.bool(forKey: disableCursorWarpKey)

        diagLog.info(
            """
            warpCursor request reason=\(reason) target=\(formattedPoint(point)) \
            beforeCG=\(formattedPoint(beforeCG)) beforeAppKit=\(formattedPoint(beforeAppKit)) \
            screenWithMouse=\(screenWithMouse.map(String.init) ?? "nil") \
            activeDisplay=\(activeDisplayID.map(String.init) ?? "nil") \
            disabledByDefault=\(disableCursorWarp) screens=[\(screenSummary(for: point))]
            """
        )

        if disableCursorWarp {
            diagLog.warning(
                """
                warpCursor skipped reason=\(reason) target=\(formattedPoint(point)) \
                because defaults key \(disableCursorWarpKey) is true
                """
            )
            return
        }

        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            diagLog.warning(
                """
                CGWarpMouseCursorPosition failed reason=\(reason) \
                target=\(formattedPoint(point)) error=\(result.rawValue); falling back to CGEvent mouseMoved
                """
            )
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

        diagLog.info(
            """
            warpCursor completed reason=\(reason) target=\(formattedPoint(point)) \
            afterCG=\(formattedPoint(locationCoreGraphics)) afterAppKit=\(formattedPoint(locationAppKit)) \
            result=\(result.rawValue)
            """
        )
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
