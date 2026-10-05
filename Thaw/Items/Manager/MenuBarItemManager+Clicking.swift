//
//  MenuBarItemManager+Clicking.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa

// @preconcurrency retained: CoreGraphics event types (CGEventSource/CGEvent) are
// still not Sendable-annotated in the macOS 26/27 SDK, yet are used off the main
// actor under OSAllocatedUnfairLock for menu-bar event posting. Removing the shim
// would force @unchecked Sendable wrappers. Drop this once Apple annotates them.
@preconcurrency import CoreGraphics
import MenuBarModel

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// How many mouse-up events a single synthetic click posts.
    ///
    /// Owners occasionally miss the first release and go on believing the
    /// button is still held, which leaves the item wedged in a pressed state.
    /// A second release costs nothing when the first one landed, so it is
    /// always sent.
    private static let clickMouseUpCount = 2

    /// Builds the press and release that make up one click on item, both
    /// aimed at point.
    private nonisolated func makeClickEvents(
        for item: MenuBarItem,
        at point: CGPoint,
        button: CGMouseButton,
        source: CGEventSource
    ) throws -> (down: CGEvent, up: CGEvent) {
        let phases = MenuBarItemEventType.pair(for: button)
        guard
            let down = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: phases.down,
                location: point
            ),
            let up = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: phases.up,
                location: point
            )
        else {
            throw EventError.eventCreationFailure(item)
        }
        return (down, up)
    }

    /// The point a synthetic click on bounds should aim at.
    ///
    /// macOS 27 mirrors one status-item set onto every bar but reports its
    /// frames in a single display's space, so a click aimed at the reported
    /// frame lands on the wrong bar when the cursor is on another one. Rebase
    /// the frame onto the display under the cursor, the bar the user is
    /// looking at. A cursor outside every menu bar leaves the frame alone,
    /// which keeps hotkey and search activation targeting the item's own bar.
    private static func clickPoint(for bounds: CGRect) -> CGPoint {
        guard
            let pointer = MouseHelpers.locationCoreGraphics,
            let screen = NSScreen.screen(containingCGPoint: pointer),
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return bounds.center
        }
        let displayBounds = CGDisplayBounds(screen.displayID)
        guard pointer.y >= displayBounds.maxY - menuBarHeight else {
            return bounds.center
        }
        let allDisplayBounds = NSScreen.allDisplayBoundsCG
        return MirroredBarGeometry.frame(
            bounds,
            on: displayBounds,
            displayBounds: allDisplayBounds
        ).center
    }

    /// Synthesizes one click on item and waits for its owner to take
    /// delivery of both halves.
    ///
    /// - Parameters:
    ///   - item: The item the click is aimed at.
    ///   - mouseButton: Which button to press and release.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        // Try to acquire semaphore with timeout. 3.5 s covers legitimate slow
        // operations (adaptive click cap is 1000 ms × 2 for double mouseUp =
        // ~2 s of event work plus overhead).
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            // The permit is still held, most likely by a synthetic drag that
            // legitimately needs it for several seconds. Resetting the
            // semaphore here would cancel that holder's queued work and let
            // this click interleave with the drag, so give up instead.
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postClickEvents for \(item.logString)")
            throw EventError.cannotComplete
        }
        defer {
            if acquiredSemaphore {
                await eventSemaphore.signal()
            }
        }

        // Re-read the item's geometry rather than trusting the caller's copy:
        // between the decision to click and this point the bar may have
        // reflowed, and clicking a stale rectangle hits a neighbour. On
        // macOS 27 the refreshed frame is stated in one display's space, so it
        // is rebased onto the bar under the cursor before the warp below.
        let resolvedBounds = try await getCurrentBounds(for: item)
        let clickPoint = Self.clickPoint(for: resolvedBounds)
        let restoreLocation = try getMouseLocation()
        let source = try getEventSource()

        try stopSuppressingLocalEvents()

        // Use adaptive timeout based on app performance history
        let timeout = getClickOperationTimeout(for: item)

        MenuBarItemManager.diagLog.debug("postClickEvents: using timeout \(Int(timeout.milliseconds))ms for \(item.logString)")

        let clickEvents = try makeClickEvents(
            for: item,
            at: clickPoint,
            button: mouseButton,
            source: source
        )

        // Warp the cursor to the click point so the Window Server's hit-test
        // matches the event coordinates rather than the cursor's current position.
        MouseHelpers.warpCursor(to: clickPoint)
        // Small delay to let the Window Server process the warp before posting
        // the event. Without this, the event can be routed using the cursor's
        // old position (e.g. the Apple menu) instead of the warped target.
        try await Task.sleep(for: .milliseconds(10))
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: restoreLocation)
            MouseHelpers.showCursor()
        }

        let eventStartTime = Date.now
        do {
            try await postEventWithBarrier(
                clickEvents.down,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                clickEvents.up,
                to: item,
                timeout: timeout,
                repeating: Self.clickMouseUpCount
            )

            let successDuration = Duration.milliseconds(Date.now.timeIntervalSince(eventStartTime) * 1000)
            updateClickOperationTimeout(successDuration, for: item)
        } catch {
            // However this failed, the owner may be sitting on a press that was
            // never released, so send the release once more on the way out.
            do {
                MenuBarItemManager.diagLog.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    clickEvents.up,
                    to: item,
                    timeout: timeout,
                    repeating: Self.clickMouseUpCount
                )
            } catch {
                // Logged and dropped on purpose: the caller needs to see what
                // actually went wrong, not how the cleanup went.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            throw error
        }
    }

    /// Activates a menu bar item by opening its menu, wherever it currently
    /// sits.
    ///
    /// The shared entry point for the per-item hotkeys and the search panel.
    /// Both hand off to clickConcealedItem(item:with:on:), which decides
    /// between clicking in place and surfacing the item first by asking the
    /// section controller where the item lives, the same dispatch the Thaw Bar
    /// and the menu bar overlay already use.
    ///
    /// This deliberately does not consult Bridging.isWindowOnScreen. macOS 27
    /// status items carry synthetic window IDs minted by
    /// MenuBarItemAXProvider, which are never in the window server's
    /// on-screen list, so that test answers false for every item and cannot
    /// separate a visible one from a concealed one.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to activate.
    ///   - displayID: The display whose menu bar hosts the item. Falls back to
    ///     the display currently showing the menu bar when the caller has none.
    /// - Returns: .completed or .activationFailed.
    @discardableResult
    func activate(item: MenuBarItem, on displayID: CGDirectDisplayID?) async -> MenuBarItemActivationOutcome {
        guard let targetDisplayID = displayID
            ?? NSScreen.screenWithActiveMenuBar?.displayID
            ?? NSScreen.main?.displayID
        else {
            MenuBarItemManager.diagLog.error(
                "Cannot activate \(item.logString): no display resolved"
            )
            return .activationFailed
        }
        return await clickConcealedItem(item: item, with: .left, on: targetDisplayID)
    }

    /// Returns whether the item's owning app is an Electron app, detected by the
    /// presence of the bundled Electron framework. Such apps ignore synthetic
    /// mouse clicks on their tray icon and must be opened via an AX press.
    func isElectronItem(_ item: MenuBarItem) -> Bool {
        let pid = resolvedPID(for: item)
        guard let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
            return false
        }
        let electronFramework = bundleURL.appendingPathComponent(
            "Contents/Frameworks/Electron Framework.framework"
        )
        return FileManager.default.fileExists(atPath: electronFramework.path)
    }

    /// Attempts to open the item's menu by performing an Accessibility press on
    /// its status item element. Returns false (so the caller can fall back to
    /// a synthetic click) when the element cannot be resolved or the press fails.
    ///
    /// The press runs off the main thread, through the AX helper when it is on:
    /// resolving the element walks the owner's extras bar, and an owner that is
    /// slow to answer would otherwise hold the main thread for every read.
    func pressItemViaAccessibility(_ item: MenuBarItem) async -> Bool {
        // Match against the item's live window bounds so a stale cached
        // position cannot send an Electron item to the synthetic click it
        // ignores.
        let itemCenter = (Bridging.getWindowBounds(for: item.windowID) ?? item.bounds).center
        return await MenuBarAXQueries.pressStatusItem(pid: resolvedPID(for: item), target: itemCenter)
    }

    /// Clicks a menu bar item and reports what its owner did about it.
    ///
    /// The paths that put nothing on the HID tap are tried first. They need no
    /// cursor warp, so the user never sees the item jitter, and a press the
    /// owner ignores cannot land somewhere else. Only a left click opens an
    /// item's primary menu, a right click means something else entirely, so it
    /// goes straight to synthetic events. If the quiet path declines, the click
    /// is synthesized and retried up to maxAttempts times.
    ///
    /// - Parameters:
    ///   - item: The item to click.
    ///   - mouseButton: Which button to click it with.
    ///   - skipInputPause: Post right away instead of first waiting for the
    ///     user to stop driving the pointer.
    ///   - maxAttempts: Maximum number of click attempts (default 3).
    /// - Returns: What the owner was observed to do in response. Callers
    ///   that need the window the click opened can read it from here
    ///   instead of scanning for it themselves.
    @discardableResult
    func click(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        skipInputPause: Bool = false,
        maxAttempts: Int = 3,
        requireObservedReaction: Bool = false
    ) async throws -> ClickReactionVerifier.Reaction {
        guard let appState else {
            throw EventError.cannotComplete
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

        // An owner marked unresponsive is deliberately not skipped here: the
        // mark records that it drops synthetic events, which is the case this
        // path is most likely to succeed at.
        if mouseButton == .left {
            if let reaction = await MenuBarItemDirectPresser.press(item: item) {
                if reaction.didReact {
                    MenuBarItemManager.diagLog.debug(
                        "Opened \(item.logString) without synthesizing events"
                    )
                    failureLedger.recordSuccess(for: item)
                    return reaction
                }
                // Some owners accept the press and open nothing. Callers that
                // need a reaction post a real click; a second activation would re-toggle the rest.
                guard requireObservedReaction else {
                    MenuBarItemManager.diagLog.debug(
                        "Pressed \(item.logString) without synthesizing events; no reaction seen"
                    )
                    return reaction
                }
                MenuBarItemManager.diagLog.debug(
                    "\(item.logString) took the press but was not seen reacting; posting a real click"
                )
            }
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // An owner already known to ignore synthetic events gets one attempt
        // instead of three. Retrying it only repeats the cursor warp that the
        // user sees as the item jittering, and the extra attempts have never
        // been what makes such an owner answer.
        let attemptBudget = failureLedger.isUnresponsive(item) ? 1 : max(1, maxAttempts)
        let attemptStartTime = Date.now

        for attempt in 1 ... attemptBudget {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                let clickStartTime = Date.now
                let snapshot = ClickReactionVerifier.snapshot(for: item)
                try await postClickEvents(item: item, mouseButton: mouseButton)
                let clickDuration = Date.now.timeIntervalSince(clickStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(attempt) succeeded in \(Int(clickDuration * 1000))ms, finished with click")

                // The events landed. Whether the owner did anything with
                // them is a separate question, and only a yes is allowed
                // to clear a standing unresponsive mark: an owner that
                // drops synthetic events acknowledges them exactly like
                // one that acts on them, so crediting the post itself
                // would forgive the very behaviour the mark records.
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
                MenuBarItemManager.diagLog.debug("Attempt \(attempt) failed after \(Int(attemptDuration * 1000))ms: \(error)")

                guard attempt == attemptBudget else {
                    await eventSleep()
                    continue
                }
                guard let error = error as? EventError else {
                    throw EventError.cannotComplete
                }
                if error.indicatesUnresponsiveOwner {
                    failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                }
                throw error
            }
        }

        // Unreachable: the loop runs at least once and every path through
        // it either returns or throws.
        throw EventError.cannotComplete
    }

    /// Reveals item at its own menu bar position, clicks it, then schedules
    /// the re-conceal. Returns whether the owner was seen reacting.
    ///
    /// No move, so it works for items the move path cannot seat. It is also
    /// the only way to right-click: AXPress opens the default action, not the
    /// secondary menu.
    func revealInPlaceAndClick(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        on displayID: CGDirectDisplayID,
        controller: any MenuBarSectionControlling
    ) async -> Bool {
        let identifier = item.uniqueIdentifier
        controller.revealItemTemporarily(identifier)

        // Same settle the prewarm uses so the AX bounds are valid. Not gated on
        // isWindowOnScreen: macOS 27 status items carry synthetic window IDs.
        await eventSleep(for: Constants.MenuBarTuning.thawBarRevealSettle)

        // Re-fetch live bounds; a transient "Item-N" title can change between
        // enumerations, so fall back to same-owner, then the cached item.
        let liveItems = await MenuBarItem.getMenuBarItems(on: displayID, option: .onScreen)
        let liveItem = liveItems.first { $0.hasSameIdentity(as: item) }
            ?? liveItems.first { $0.hasSameOwner(as: item) }
            ?? item

        let reacted: Bool
        do {
            reacted = try await click(item: liveItem, with: mouseButton, requireObservedReaction: true).didReact
        } catch {
            MenuBarItemManager.diagLog.error(
                "revealInPlaceAndClick: click failed for \(item.logString): \(error)"
            )
            reacted = false
        }
        guard reacted else {
            // Nothing opened, so nothing to wait for; the next method starts
            // from a concealed item.
            controller.concealTemporarilyRevealedItem(identifier)
            return false
        }

        // Let the opened menu settle before scheduling the re-conceal.
        await eventSleep(for: Constants.MenuBarTuning.thawBarPostClickSettle)
        controller.scheduleTemporaryItemConceal(identifier)
        return true
    }
}
