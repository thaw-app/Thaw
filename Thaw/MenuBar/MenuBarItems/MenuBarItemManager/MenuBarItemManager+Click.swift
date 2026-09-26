//
//  MenuBarItemManager+Click.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// Returns the equivalent event subtypes for clicking a menu bar
    /// item with the given mouse button.
    private nonisolated func getClickSubtypes(
        for mouseButton: CGMouseButton
    ) -> (down: MenuBarItemEventType.ClickSubtype, up: MenuBarItemEventType.ClickSubtype) {
        switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    /// Creates and posts a series of events to click a menu bar item.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        // 3.5 s covers the slowest legit click: adaptive cap 1000 ms × 2 mouseUps, plus overhead.
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postClickEvents for \(item.logString), retrying once")
            do {
                try await eventSemaphore.wait(timeout: .milliseconds(3500))
                acquiredSemaphore = true
            } catch is SimpleSemaphore.TimeoutError {
                throw EventError.cannotComplete
            }
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        let clickPoint = try await getCurrentBounds(for: item).center

        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        let clickTypes = getClickSubtypes(for: mouseButton)
        let timeout = getClickOperationTimeout(for: item)

        MenuBarItemManager.diagLog.debug("postClickEvents: using timeout \(Int(timeout.milliseconds))ms for \(item.logString)")

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        // Warp so WindowServer hit-tests the event point, not the old cursor position.
        MouseHelpers.warpCursor(to: clickPoint)
        // Without this delay the event can be routed by the pre-warp cursor
        // position (e.g. the Apple menu).
        try await Task.sleep(for: .milliseconds(10))
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.restoreCursorPosition(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        let eventStartTime = Date.now
        do {
            try await postEventWithBarrier(
                mouseDown,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                mouseUp,
                to: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )

            let successDuration = Duration.milliseconds(Date.now.timeIntervalSince(eventStartTime) * 1000)
            updateClickOperationTimeout(successDuration, for: item)
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    mouseUp,
                    to: item,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Log only; the original error is the one to propagate.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            throw error
        }
    }

    /// Opens an item's menu. On-screen items are clicked in place; off-screen
    /// ones go through temporarilyShow, which moves, clicks, and rehides them.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to activate.
    ///   - displayID: The display whose menu bar hosts a temporary reveal for
    ///     off-screen items.
    func activate(item: MenuBarItem, on displayID: CGDirectDisplayID?) async {
        if Bridging.isWindowOnScreen(item.windowID) {
            // Electron tray items ignore synthetic clicks, so use an AX press. Everything
            // else gets a real click, which keeps the native toggle and doesn't disturb
            // popover menus (e.g. Cap, Droppy) the way AX can.
            if isElectronItem(item), pressItemViaAccessibility(item) {
                MenuBarItemManager.diagLog.info("Activated \(item.logString) via AX press")
                return
            }
            do {
                try await click(item: item, with: .left)
            } catch {
                MenuBarItemManager.diagLog.error("Failed to activate \(item.logString): \(error)")
            }
        } else {
            await temporarilyShow(item: item, clickingWith: .left, on: displayID)
        }
    }

    /// Detected by the bundled Electron framework. These apps ignore synthetic
    /// clicks on their tray icon and need an AX press.
    func isElectronItem(_ item: MenuBarItem) -> Bool {
        // Fall back to ownerPID so this works during startup before sourcePID
        // has been resolved.
        let pid = item.sourcePID ?? item.ownerPID
        guard let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
            return false
        }
        let electronFramework = bundleURL.appendingPathComponent(
            "Contents/Frameworks/Electron Framework.framework"
        )
        return FileManager.default.fileExists(atPath: electronFramework.path)
    }

    /// Opens the item's menu with an AX press. Returns false when the element
    /// can't be resolved or the press fails, so the caller can click instead.
    func pressItemViaAccessibility(_ item: MenuBarItem) -> Bool {
        // Fall back to ownerPID so this works during startup before sourcePID
        // has been resolved.
        let pid = item.sourcePID ?? item.ownerPID
        guard
            let runningApp = NSRunningApplication(processIdentifier: pid),
            let app = AXHelpers.application(for: runningApp),
            let extrasMenuBar = AXHelpers.extrasMenuBar(for: app)
        else {
            return false
        }

        let children = AXHelpers.children(for: extrasMenuBar)
        guard !children.isEmpty else {
            return false
        }

        // A single status item is unambiguous. With several, match the one whose
        // AX frame lines up with this item's window so the right menu opens.
        let target: UIElement
        if children.count == 1 {
            target = children[0]
        } else {
            // Live bounds: a stale cached position can mismatch and send an
            // Electron item to the synthetic click it ignores.
            let itemCenter = (item.liveBounds).center
            guard
                let best = children.min(by: { lhs, rhs in
                    let lhsDistance = AXHelpers.frame(for: lhs)?.center.distance(to: itemCenter) ?? .greatestFiniteMagnitude
                    let rhsDistance = AXHelpers.frame(for: rhs)?.center.distance(to: itemCenter) ?? .greatestFiniteMagnitude
                    return lhsDistance < rhsDistance
                }),
                let bestFrame = AXHelpers.frame(for: best),
                bestFrame.center.distance(to: itemCenter) <= 10
            else {
                return false
            }
            target = best
        }

        return AXHelpers.press(target)
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    ///   - skipInputPause: Skip waiting for user input to pause.
    ///   - maxAttempts: Maximum number of click attempts (default 3).
    ///     Pass `1` from `temporarilyShow` so a single failure returns
    ///     immediately and the caller's fallback path fires promptly.
    /// - Returns: What the owner was observed to do in response. Callers
    ///   that need the window the click opened can read it from here
    ///   instead of scanning for it themselves.
    @discardableResult
    func click(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        skipInputPause: Bool = false,
        maxAttempts: Int = 3
    ) async throws -> ClickReactionVerifier.Reaction {
        guard let appState else {
            throw EventError.cannotComplete
        }

        if mouseButton == .left, appState.settings.advanced.useAXClickDelivery == true {
            let snapshot = ClickReactionVerifier.snapshot(for: item)
            do {
                try await AXItemActivator.activate(item: item)
                MenuBarItemManager.diagLog.debug("Activated \(item.logString) via AX click delivery")
                return await ClickReactionVerifier.verify(against: snapshot)
            } catch {
                // The fallback is a click, which would shut a menu that already
                // opened. This covers errors thrown before the activator's own check.
                let reaction = await ClickReactionVerifier.verify(against: snapshot)
                if reaction.didReact {
                    MenuBarItemManager.diagLog.debug(
                        "AX activation reported \(error) but \(item.logString) reacted; not clicking on top of it"
                    )
                    return reaction
                }
                MenuBarItemManager.diagLog.debug("AX activation failed (\(error)), falling back to synthetic click")
            }
        }

        if !skipInputPause {
            try await waitForUserToPauseInput()
        }

        MenuBarItemManager.diagLog.info(
            """
            Clicking \(item.logString) with \
            \(mouseButton.logString)
            """
        )

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // Known-unresponsive owners get one attempt; retries only add visible
        // cursor-warp jitter and have never made such an owner answer.
        let maxAttempts: Int = if failureLedger.isUnresponsive(item) {
            1
        } else {
            max(1, maxAttempts)
        }
        let attemptStartTime = Date.now
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                let clickStartTime = Date.now
                let snapshot = ClickReactionVerifier.snapshot(for: item)
                try await postClickEvents(item: item, mouseButton: mouseButton)
                let clickDuration = Date.now.timeIntervalSince(clickStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded in \(Int(clickDuration * 1000))ms, finished with click")

                // Only an observed reaction clears the unresponsive mark: an owner
                // that drops synthetic events acknowledges the post like one that acts.
                let reaction = await ClickReactionVerifier.verify(against: snapshot)
                if reaction.didReact {
                    failureLedger.recordSuccess(for: item)
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "\(item.logString) acknowledged the click but was not seen reacting to it"
                    )
                }
                return reaction
            } catch {
                let attemptDuration = Date.now.timeIntervalSince(attemptStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(n) failed after \(Int(attemptDuration * 1000))ms: \(error)")
                if n < maxAttempts {
                    await eventSleep()
                    continue
                }
                if let error = error as? EventError {
                    if error.indicatesUnresponsiveOwner {
                        failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    }
                    throw error
                }
                throw EventError.cannotComplete
            }
        }

        // Unreachable: the loop runs at least once and every path through
        // it either returns or throws.
        throw EventError.cannotComplete
    }
}
