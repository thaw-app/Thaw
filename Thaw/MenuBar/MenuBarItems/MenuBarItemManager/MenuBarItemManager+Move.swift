//
//  MenuBarItemManager+Move.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    nonisolated enum MoveDestination: Equatable {
        /// The destination to the left of the given target item.
        case leftOfItem(MenuBarItem)
        /// The destination to the right of the given target item.
        case rightOfItem(MenuBarItem)

        /// The destination's target item.
        var targetItem: MenuBarItem {
            switch self {
            case let .leftOfItem(item), let .rightOfItem(item): item
            }
        }

        /// Returns the drag point for placing an item relative to the target bounds.
        ///
        /// Targets parked beyond the display's left edge use their vertical
        /// midpoint so a synthetic event clamped to the edge cannot land on a
        /// top Hot Corner. On-screen targets retain the existing top-edge
        /// coordinate to avoid changing normal cursor-warp behavior.
        func targetPoint(in targetBounds: CGRect, on displayBounds: CGRect) -> CGPoint {
            let targetIsParkedOffscreen = targetBounds.maxX <= displayBounds.minX
            let targetY = targetIsParkedOffscreen ? targetBounds.midY : targetBounds.minY
            // Dropping on a divider's own edge leaves AppKit free to choose
            // either side of it, and in #923 it chose wrong every time:
            // .leftOfItem(AH_ctrl) landed the item at the divider's minX + 1,
            // one point into the section the user was dragging out of. Bias
            // one point into the requested section so the synthetic event's
            // target X is unambiguous.
            //
            // This was once gated to zero-width dividers, on the theory that
            // a divider with span gives AppKit enough hit-test width to
            // resolve the side on its own. The 21 August log kills that
            // theory: the same reporter's AH_ctrl was thousands of points
            // wide (parked, maxX ≤ 0, expanded to conceal the section) and
            // the drop still landed at minX + 1 on attempts 1 and 5, with
            // the ordinal check correctly rejecting both. A divider's width
            // is its concealment mechanism, not hit-test slack; what matters
            // is that the drop point is its edge, which is the boundary
            // itself.
            // The chevron is excluded: it is a control item but not a
            // section boundary, and TemporaryShow anchors moves directly on
            // it with .leftOfItem — biasing those drops would place the item
            // one point left of an anchor that is not an edge between two
            // sections, for no hit-test ambiguity resolved.
            let sectionBias: CGFloat = targetItem.tag == .hiddenControlItem
                || targetItem.tag == .alwaysHiddenControlItem ? 1 : 0
            return switch self {
            case .leftOfItem:
                CGPoint(x: targetBounds.minX - sectionBias, y: targetY)
            case .rightOfItem:
                CGPoint(x: targetBounds.maxX + sectionBias, y: targetY)
            }
        }

        /// Whether a synthetic drag to this destination would press at a
        /// point that lies off every display.
        ///
        /// ``targetPoint(in:on:)`` derives the drop point from the target's
        /// leading or trailing edge, so a target parked in the off-screen
        /// zone yields a press no owner is watching: the events are accepted,
        /// AppKit drops the item beside the parked target, and the item is
        /// stranded there. ``LayoutSolver/isOnScreen(bounds:screenFrames:)``
        /// is the matching test — it measures the leading edge, which is the
        /// edge a drop point is built from.
        ///
        /// Answering true is not on its own a reason to refuse a move. A
        /// collapsed section parks its divider and its items off-screen by
        /// design, so every drop that conceals an item answers true and is
        /// still correct. Callers pair this with the moved item's desired
        /// section: only an item bound for the visible section is stranded
        /// by a target that answers true.
        func wouldLandOffScreen(screenFrames: [CGRect]) -> Bool {
            !LayoutSolver.isOnScreen(bounds: targetItem.bounds, screenFrames: screenFrames)
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case let .leftOfItem(item): "left of \(item.logString)"
            case let .rightOfItem(item): "right of \(item.logString)"
            }
        }
    }

    /// Returns a safe location for an off-screen move's initial mouse-down.
    ///
    /// `NSScreen` frames use AppKit coordinates, while `CGEvent` locations use
    /// Core Graphics coordinates. Their horizontal axes align, so the notch
    /// supplies only the x-coordinate; the target supplies the event's y-coordinate.
    static nonisolated func notchMouseDownPoint(
        notchFrameAppKit: CGRect,
        targetPointCoreGraphics: CGPoint
    ) -> CGPoint {
        CGPoint(x: notchFrameAppKit.midX, y: targetPointCoreGraphics.y)
    }

    /// Returns the default timeout for move operations associated
    /// with the given item.
    ///
    /// A budget, not a cost. `waitForMoveEventResponse` polls the item's
    /// origin every 10ms and returns the instant it changes, so an owner that
    /// answers promptly is charged what it takes and nothing more. Raising
    /// these values cannot slow a move that works; it only buys time for one
    /// that would otherwise have been abandoned while it was still going to
    /// succeed.
    ///
    /// 100ms was too little to survive contention. In the #687 log, of the
    /// twelve moves that landed, five needed a second or third attempt — the
    /// owners were answering, just not inside the budget — and only twelve of
    /// thirty-two moves landed at all. Startup is the worst case for this:
    /// the source-PID scan and the restore wave compete for the same
    /// main threads the AX and event round-trips have to be serviced on.
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Bento Boxes (i.e. Control Center groups) generally
            // take a little longer to respond.
            return .milliseconds(350)
        }
        return .milliseconds(250)
    }

    /// Returns the cached timeout for move operations associated
    /// with the given item.
    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Merges a newly computed timeout with the one currently cached for an
    /// item.
    ///
    /// Growth is adopted as computed; only shrinkage is smoothed against the
    /// standing value. Averaging both directions halved every escalation step
    /// and so undid the one `nextMoveOperationTimeout` had just decided on:
    /// a budget escalating by half from 100ms reaches the ceiling in four
    /// attempts, but smoothed it only reaches 476ms in eight, which is the
    /// exact ladder the #687 log walks before giving up on 1Password
    /// (0.1 → 0.125 → 0.156 → 0.195 → 0.244 → 0.305 → 0.381 → 0.476). The
    /// attempts meant to be spent trying a bigger budget were spent creeping
    /// toward one instead. Decay stays smoothed, because there the caution is
    /// the point: one fast answer should not commit an owner to a budget it
    /// cannot meet again.
    ///
    /// The floor is 75ms: `waitForMoveEventResponse` polls every 10ms, so a
    /// budget below that leaves too little margin for system event latency and
    /// causes `itemResponseTimeout` → retry cascades. The ceiling is a second,
    /// which is what an escalating budget is allowed to cost before the item is
    /// better classified as unresponsive than as slow.
    static nonisolated func mergedMoveOperationTimeout(
        proposed: Duration,
        current: Duration
    ) -> Duration {
        let next = proposed > current ? proposed : (proposed + current) / 2
        return next.clamped(min: .milliseconds(75), max: .seconds(1))
    }

    /// Watchdog duration that covers the worst case of a single `move`
    /// call: every one of `maxAttempts` attempts spends its whole
    /// operation timeout four times over (two event posts, two response
    /// waits), budgets can escalate to the merged ceiling, and a failed
    /// attempt posts one more fallback at a fixed 100 ms. The result never
    /// drops below the historical flat 10 s, so ordinary moves keep the
    /// same safety net while an escalated stubborn item no longer outlasts
    /// the watchdog and force-shows the cursor mid-sequence.
    ///
    /// Extracted so the arithmetic is unit-testable without posting events.
    static nonisolated func cursorHideWatchdogTimeout(
        operationCeiling: Duration = .seconds(1),
        maxAttempts: Int = 8,
        fallbackPost: Duration = .milliseconds(100),
        floor: Duration = .seconds(10)
    ) -> Duration {
        // Per attempt: two event posts + two response waits, all capped at
        // the ceiling. One millisecond is 10^15 attoseconds.
        let attosecondsPerMillisecond = 1_000_000_000_000_000.0
        let perAttemptComponents = operationCeiling.components
        let perAttemptMs = Double(perAttemptComponents.seconds) * 1000.0
            + Double(perAttemptComponents.attoseconds) / attosecondsPerMillisecond
        let attempts = max(1, maxAttempts)
        let fallbackMs = Double(fallbackPost.components.seconds) * 1000.0
            + Double(fallbackPost.components.attoseconds) / attosecondsPerMillisecond
        let floorMs = Double(floor.components.seconds) * 1000.0
            + Double(floor.components.attoseconds) / attosecondsPerMillisecond
        let totalMs = max(floorMs, perAttemptMs * Double(attempts) * 4 + fallbackMs)
        return .milliseconds(Int(totalMs.rounded(.up)))
    }

    /// Updates the cached timeout for move operations associated
    /// with the given item.
    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        moveOperationTimeouts[item.tag] = Self.mergedMoveOperationTimeout(
            proposed: timeout,
            current: getMoveOperationTimeout(for: item)
        )
    }

    /// Prunes the move operation timeouts cache, keeping only the entries
    /// for the given valid tags.
    func pruneMoveOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        moveOperationTimeouts = moveOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// Returns the default timeout for click operations based on the item's namespace.
    private func getDefaultClickOperationTimeout(for item: MenuBarItem) -> Duration {
        // Known slow apps with dynamic content
        let slowAppBundleIDs = [
            "com.bitsplash.PasteNow",
            "com.charliemonroe.Downie-setapp",
            "com.if.Amphetamine",
            "com.hegenberg.BetterTouchTool",
            "net.matthewpalmer.Vanilla",
        ]

        let namespaceString = item.tag.namespace.description
        if slowAppBundleIDs.contains(where: { namespaceString.contains($0) }) {
            return .milliseconds(500) // Extra time for slow apps
        }

        return .milliseconds(350) // Default
    }

    /// Returns the cached timeout for click operations associated with the given item.
    func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = clickOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultClickOperationTimeout(for: item)
    }

    /// Updates the cached timeout for click operations associated with the given item.
    func updateClickOperationTimeout(_ duration: Duration, for item: MenuBarItem) {
        let current = getClickOperationTimeout(for: item)
        let average = (duration + current) / 2
        let clamped = average.clamped(min: .milliseconds(200), max: .milliseconds(1000))
        clickOperationTimeouts[item.tag] = clamped
        MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(duration.milliseconds))ms)")
    }

    /// Prunes the click operation timeouts cache, keeping only the entries
    /// for the given valid tags.
    func pruneClickOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickOperationTimeouts = clickOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)

        let start = destination.targetPoint(
            in: targetBounds,
            on: CGDisplayBounds(displayID)
        )
        let end = start

        MenuBarItemManager.diagLog.debug(
            "Move points: startX=\(start.x) endX=\(end.x) startY=\(start.y) targetMinX=\(targetBounds.minX) itemMinX=\(itemBounds.minX) targetTag=\(destination.targetItem.tag) itemTag=\(item.tag) display=\(displayID)"
        )
        return (start, end)
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    /// Reports whether `item` is now the immediate neighbor of the
    /// destination's target on the requested side.
    ///
    /// This asks for the ordinal relationship rather than comparing
    /// coordinates. The check used to re-read both rects independently and
    /// compare them for exact `CGFloat` equality, which cannot succeed on a
    /// bar that reflows: our own drag displaces the target too, so the item
    /// lands where the target *was* and is then compared against where the
    /// target now is. In the #881 log the target's measured `minX` swung from
    /// -4222 to 794 between attempts while the item sat still, and all eight
    /// attempts were spent re-dragging against a destination that had already
    /// moved (#900).
    ///
    /// Reading one list fixes that: both operands come from the same snapshot,
    /// so they cannot drift apart mid-check. It also sidesteps
    /// ``getCurrentBounds(for:)`` mixing coordinate spaces — its windowID path
    /// answers for parked offscreen windows while its tag-matching fallback
    /// answers from the on-screen list, and which one runs depends on timing.
    ///
    /// - Note: source PIDs are deliberately left unresolved. Only tags, window
    ///   IDs and bounds are needed here, and this runs once per attempt.
    ///
    /// Main-actor isolated rather than `nonisolated`: the enumeration and the
    /// tag comparison both are, and hopping once per attempt costs nothing
    /// next to the enumeration itself.
    private func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws -> Bool {
        // Not `.onScreen`: an item moved into a collapsed section is parked
        // offscreen, and that is a landing we still have to be able to confirm.
        let items = await MenuBarItem
            .getMenuBarItems(on: displayID, option: .activeSpace, resolveSourcePID: false)
            .sorted { $0.bounds.minX < $1.bounds.minX }

        /// Prefer the exact window, falling back to the tag, matching the
        /// preference order `getCurrentBounds(for:)` already uses.
        func index(of needle: MenuBarItem) -> Int? {
            items.firstIndex { $0.windowID == needle.windowID }
                ?? items.firstIndex(matching: needle.tag)
        }

        guard
            let itemIndex = index(of: item),
            let targetIndex = index(of: destination.targetItem)
        else {
            // One of the two no longer enumerates on this display's active
            // space, so the landing cannot be confirmed either way. Report a
            // miss and let the caller's attempt budget decide what happens.
            return false
        }

        return switch destination {
        case .leftOfItem: itemIndex == targetIndex - 1
        case .rightOfItem: itemIndex == targetIndex + 1
        }
    }

    /// Waits for a menu bar item to respond to a series of previously
    /// posted move events.
    ///
    /// - Parameters:
    ///   - item: The item to check for a response.
    ///   - initialOrigin: The origin of the item before the events were posted.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForMoveEventResponse(
        from item: MenuBarItem,
        initialOrigin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let responseTask = Task.detached {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            let origin = try await timeoutTask.value
            MenuBarItemManager.diagLog.debug(
                """
                Item responded to events with new origin: \
                \(String(describing: origin))
                """
            )
            return origin
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        } catch {
            MenuBarItemManager.diagLog.debug("waitForItemResponse: wait for \(item.logString) failed: \(error)")
            throw EventError.cannotComplete
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    private func postMoveEvents(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        warpCursorAfter: Bool = true
    ) async throws -> Duration {
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postMoveEvents, retrying once")
            do {
                try await eventSemaphore.wait(timeout: .milliseconds(3500))
                acquiredSemaphore = true
            } catch is SimpleSemaphore.TimeoutError {
                MenuBarItemManager.diagLog.error("postMoveEvents: eventSemaphore retry also timed out; giving up on \(item.logString)")
                throw EventError.cannotComplete
            }
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        // Fast-fail if the target process is dead. CGEvent.tapCreateForPid
        // silently produces an invalid Mach port for dead PIDs, causing every
        // scrombleEvent to time out and burn the full 3.5 s semaphore budget.
        let eventPID = getEventPID(for: item)
        if kill(eventPID, 0) == -1, errno == ESRCH {
            MenuBarItemManager.diagLog.error("postMoveEvents: target PID \(eventPID) for \(item.logString) is dead; skipping move")
            throw EventError.cannotComplete
        }

        // A process that is alive but not pumping its event loop never
        // acknowledges the synthetic move, so every scrombleEvent below runs
        // to its timeout and burns the full 3.5 s semaphore budget — with the
        // semaphore held, that stalls every *other* item's move behind it.
        // Little Snitch is the recurring case (it ships with GUI Scripting
        // disabled), but this catches any hung owner. Bail out immediately
        // instead; the caller's retry/backoff path picks the item up again
        // once its owner starts responding.
        if Bridging.isProcessUnresponsive(eventPID) {
            MenuBarItemManager.diagLog.warning(
                "postMoveEvents: target PID \(eventPID) for \(item.logString) is unresponsive; skipping move"
            )
            throw EventError.ownerUnresponsive(item)
        }

        let itemBounds = try await getCurrentBounds(for: item)
        var itemOrigin = itemBounds.origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination, on: displayID)

        // Press and release at the *destination* (targetPoints.start == .end
        // == the target edge) with the moved item's window ID stamped on the
        // press, relying on the owner to relocate its item to the press
        // location. Every move observed in #881 needed a warm-up attempt
        // before that took: the first press nudged the item a pixel, the
        // second teleported it. A drag-gesture geometry was trialled behind
        // a setting to remove that warm-up and did not fix it, so it was
        // withdrawn; the warm-up attempt remains an open problem.
        let pressPoint = targetPoints.start

        // Capture mouse location only when this call owns the cursor warp.
        // When called from move(), the outer move() handles the single warp
        // at the end of all attempts so the cursor doesn't oscillate per attempt.
        let mouseLocation: CGPoint? = warpCursorAfter ? try getMouseLocation() : nil
        let source = try getEventSource()

        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: pressPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: destination.targetItem,
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        var timeout = getMoveOperationTimeout(for: item)
        MenuBarItemManager.diagLog.debug("Move operation timeout: \(timeout)")

        lastMoveOperationTimestamp = .now
        // Skip the warp when the target is offscreen (negative-X items in
        // hidden/always-hidden on notch displays). CGWarpMouseCursorPosition
        // clamps to the display's leftmost edge, which sits under the Apple
        // menu, and the resulting tracking events then route stray clicks
        // there. The 20ms eventSleep that follows the warp is only needed
        // when slow apps have to register the tracking events before the
        // mouseDown; irrelevant offscreen.
        let warpPoint = pressPoint
        let warpIsOnScreen = NSScreen.screens.contains {
            CGDisplayBounds($0.displayID).contains(warpPoint)
        }
        if warpIsOnScreen {
            // Load-bearing for event delivery — keep unconditionally, even
            // during a bulk apply: the receiving app's tracking needs the
            // cursor at the target location regardless of its visibility.
            MouseHelpers.warpCursor(to: warpPoint)
        }
        // During a bulk apply (applyProfileLayout's move sequence) the
        // cursor is already held hidden for the whole sequence and
        // restored once at its end (Phase 7). Hiding/showing again per
        // item here is redundant churn and, if the outer hide's refcount
        // is ever force-reset by its watchdog mid-sequence, is what turns
        // into the cursor visibly "yanked" across every remaining item's
        // move (#723). Skip it and rely on the sequence-level hide.
        // Sampled once and reused by the defer below. Reading the flag a
        // second time at defer time is not safe: a bulk apply can start
        // while this move is parked on one of the awaits in between, which
        // would pair a hide here with no show at all and strand the cursor
        // hidden until the bulk apply's 30 s watchdog fires.
        let ownsCursorVisibility = !isBulkApplyInProgress
        if ownsCursorVisibility {
            MouseHelpers.hideCursor()
        }
        if warpIsOnScreen {
            await eventSleep(for: .milliseconds(20))
        }
        // For notched displays, when the target is offscreen, redirect
        // mouseDown's horizontal hit-test location into the notch itself. The
        // notch is hardware with no clickable UI, so the OS hit-test there has
        // nothing to dismiss, no menu to open, and no app window to surface a
        // click against. Keep the Core Graphics y-coordinate inside the menu
        // bar; frameOfNotch is in AppKit coordinates and its y-coordinate would
        // instead point near the bottom of the display. mouseUp keeps its
        // original location (the drop position the receiving app uses to place
        // the item). For non-notched displays the original behaviour is
        // preserved (no override).
        if !warpIsOnScreen {
            let activeScreen = NSScreen.screens.first(where: { $0.displayID == displayID })
                ?? NSScreen.main
            if let activeScreen,
               activeScreen.hasNotch,
               let notch = activeScreen.frameOfNotch
            {
                mouseDown.location = Self.notchMouseDownPoint(
                    notchFrameAppKit: notch,
                    targetPointCoreGraphics: targetPoints.start
                )
            }
        }
        defer {
            if let mouseLocation {
                MouseHelpers.restoreCursorPosition(to: mouseLocation)
            }
            // Mirrors the skipped hideCursor() above: during a bulk apply
            // the sequence-level restoration (applyProfileLayout Phase 7)
            // owns showing the cursor once, at the end.
            if ownsCursorVisibility {
                MouseHelpers.showCursor()
            }
            lastMoveOperationTimestamp = .now
        }

        do {
            try await scrombleEvent(
                mouseDown,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                mouseUp,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: item,
                    timeout: .milliseconds(100), // Fixed timeout for fallback.
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            timeout = Self.nextMoveOperationTimeout(after: timeout, outcome: .ownerDidNotRespond)
            updateMoveOperationTimeout(timeout, for: item)
            throw error
        }
        return timeout
    }

    /// Checks if a menu bar item is in a "blocked" state (positioned at x=-1 off-screen).
    /// Items in this state are stuck and cannot be interacted with normally.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try await getCurrentBounds(for: item)
            // x=-1 is the sentinel value macOS uses for "blocked" items
            return bounds.origin.x == -1
        } catch {
            // If we can't get bounds, assume it's not blocked
            return false
        }
    }

    /// Validates that an item moved to the hidden section didn't get stuck at x=-1.
    /// If the item is blocked, attempts to restore it to the visible section.
    private func validateItemPositionAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async {
        // Only recover items that got stuck when targeting the hidden divider.
        // Items placed adjacent to any other anchor are intentionally positioned;
        // recovering them to visible would undo a correct move.
        switch destination {
        case let .leftOfItem(anchor), let .rightOfItem(anchor):
            guard anchor.tag == .alwaysHiddenControlItem else { return }
        }

        // Check if item got stuck at x=-1
        if await isItemBlocked(item) {
            MenuBarItemManager.diagLog.warning("Item \(item.logString) stuck at x=-1 after move - attempting recovery")

            // Find the control item to use as anchor for recovery
            guard let appState else { return }
            guard let hiddenControlItem = appState.menuBarManager.controlItem(withName: .hidden)?.window else {
                MenuBarItemManager.diagLog.error("Cannot recover item: missing hidden control item window")
                return
            }

            // Create a MenuBarItem representation of the control item for the destination
            // We need to find it in the current cache
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard let hiddenMenuBarItem = items.first(where: { $0.windowID == CGWindowID(hiddenControlItem.windowNumber) }) else {
                MenuBarItemManager.diagLog.error("Cannot recover item: control item not found in menu bar items")
                return
            }

            // Attempt to move the item back to the visible section
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(hiddenMenuBarItem),
                    on: displayID,
                    skipInputPause: true
                )
                MenuBarItemManager.diagLog.info("Successfully recovered \(item.logString) from blocked state to visible section")
            } catch {
                MenuBarItemManager.diagLog.error("Failed to recover \(item.logString) from blocked state: \(error)")
            }
        }
    }

    /// Returns whether the given item is currently in the "blocked" state
    /// (positioned at x=-1). Exposed so drag-failure callers can classify a
    /// failed move without duplicating the sentinel check performed by
    /// `isItemBlocked`.
    func isItemCurrentlyBlocked(_ item: MenuBarItem) async -> Bool {
        await isItemBlocked(item)
    }

    /// Attempts to move a blocked (x=-1) item back to the visible section,
    /// immediately right of the hidden control item — the same safe-harbor
    /// anchor used by `restoreBlockedItemsToVisible` and
    /// `validateItemPositionAfterMove`. This does not retry the original
    /// move; callers are responsible for retrying afterward if desired.
    ///
    /// - Returns: `true` if the rescue move completed without throwing.
    func rescueBlockedItemToVisible(_ item: MenuBarItem) async -> Bool {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let hiddenMenuBarItem = items.first(matching: .hiddenControlItem) else {
            MenuBarItemManager.diagLog.error("Cannot rescue blocked item \(item.logString): hidden control item not found")
            return false
        }
        do {
            try await move(
                item: item,
                to: .rightOfItem(hiddenMenuBarItem),
                skipInputPause: true,
                options: .init(watchdogTimeout: Self.layoutWatchdogTimeout)
            )
            return true
        } catch {
            MenuBarItemManager.diagLog.error("Failed to rescue blocked item \(item.logString): \(error)")
            return false
        }
    }

    /// The outcome to take when a hidden-section drag's move throws after
    /// the drag handler's resample-and-verify pass.
    nonisolated enum HiddenDragFailureAction: Equatable {
        /// The item actually reached its intended position; the throw was a
        /// false alarm from verification racing macOS's own settle. No
        /// alert needed.
        case suppress
        /// The item is stuck at the x=-1 sentinel. It can be rescued to the
        /// visible section and the original move retried once.
        case rescueAndRetry
        /// The hidden-section control item couldn't be resolved; recovery
        /// is already running in the background (see plan 004). Show a
        /// calm, specific message instead of the raw error.
        case alertControlItemsMissing
        /// None of the above; show the raw error as before.
        case alertGeneric
    }

    /// Pure classification of a failed hidden-section drag, used to decide
    /// whether to suppress, rescue-and-retry, or alert (and with which
    /// message). Precedence: reaching the position beats being blocked;
    /// being blocked beats missing control items.
    static nonisolated func classifyHiddenDragFailure(
        reachedPosition: Bool,
        isBlocked: Bool,
        controlItemsMissing: Bool
    ) -> HiddenDragFailureAction {
        if reachedPosition {
            .suppress
        } else if isBlocked {
            .rescueAndRetry
        } else if controlItemsMissing {
            .alertControlItemsMissing
        } else {
            .alertGeneric
        }
    }

    /// The tunables of a single synthetic-drag move. Every field defaults,
    /// so callers pass only what they deviate from; the whole struct exists
    /// so ``move`` and ``moveItem(withTagIdentifier:toSection:options:)``
    /// stay readable at the call site.
    struct MoveOptions {
        var requiredInputPause: Duration?
        var inputPauseTimeout: Duration?
        var watchdogTimeout: Duration?
        var maxMoveAttempts: Int = 8
        var hideCursorAcrossAttempts: Bool = true
        var shouldProceed: (@MainActor () -> Bool)?
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    ///   - options: The move tunables; every field defaults, so callers only
    ///     pass what they deviate from.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        options: MoveOptions = .init()
    ) async throws {
        // System clone windows are transient WindowServer duplicates that
        // must never be moved. Refuse here as a final safety net so no
        // planning path can drag a phantom and displace real items. The
        // planners filter clones earlier; this backstops every move caller.
        // A no-op is correct: the clone has no managed position to restore
        // and will vanish on its own, so there's nothing to fail or retry.
        guard !item.isSystemClone else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - system status item clone")
            return
        }
        guard item.isMovableAddressingWindowOwner else {
            // The refusal used to be silent (#905): name the gate and the
            // identifier the decision was made on, so a report can tell a
            // static macOS prohibition from an identity-resolution failure.
            MenuBarItemManager.diagLog.warning(
                "move: refusing \(item.logString): \(item.immovabilityReason?.logDescription ?? "isMovable false with no named gate"); uniqueIdentifier=\(item.uniqueIdentifier), sourcePID=\(item.sourcePID.map(String.init) ?? "nil")"
            )
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            MenuBarItemManager.diagLog.error("move: no appState; cannot move \(item.logString)")
            throw EventError.cannotComplete
        }
        guard options.shouldProceed?() ?? true else {
            throw EventError.moveSuperseded(item)
        }

        // Never drag an item while a menu bar item menu is tracking — a synthetic
        // Cmd-drag tears down the user's interaction (Wi-Fi picker, input methods).
        // Wait briefly for the menu to close; if it stays open, give up this attempt.
        var menuWaitAttempts = 0
        while await isAnyMenuBarItemMenuOpen() {
            guard options.shouldProceed?() ?? true else {
                throw EventError.moveSuperseded(item)
            }
            menuWaitAttempts += 1
            if menuWaitAttempts > 20 { // ~5s at 250ms steps
                MenuBarItemManager.diagLog.warning("move: menu still open after wait; deferring move of \(item.logString)")
                throw EventError.menuTrackingActive(item)
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        // Allow right-of-item moves to proceed even when the item is at x=-1.
        // validateItemPositionAfterMove uses exactly this path to rescue stuck
        // items. Block all other moves: dragging a stuck item deeper into a
        // hidden section could leave it in an unknown position.
        if await isItemBlocked(item) {
            guard case .rightOfItem = destination else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        // Determine display ID early.
        let resolvedDisplayID: CGDirectDisplayID = if let displayID {
            displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            window.displayID
        } else {
            Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        if !skipInputPause {
            let inputPauseResult = try await waitForUserToPauseInput(
                for: options.requiredInputPause,
                timeout: options.inputPauseTimeout,
                shouldContinue: options.shouldProceed
            )
            switch inputPauseResult {
            case .paused:
                break
            case .timedOut:
                throw EventError.inputPauseTimedOut(item)
            case .superseded:
                throw EventError.moveSuperseded(item)
            }
        }
        guard options.shouldProceed?() ?? true else {
            throw EventError.moveSuperseded(item)
        }
        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        try await waitForMoveOperationBuffer()

        MenuBarItemManager.diagLog.info(
            """
            Moving \(item.logString) to \
            \(destination.logString) on display \(resolvedDisplayID)
            """
        )

        guard try await !itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) else {
            MenuBarItemManager.diagLog.debug("Item has correct position, cancelling move")
            return
        }

        // Capture the original cursor position once so the cursor is warped
        // back to it a single time after all attempts, rather than after each
        // individual attempt (which caused the cursor to oscillate many times
        // during a layout reset when items required multiple attempts).
        let mouseLocation = options.hideCursorAcrossAttempts ? try getMouseLocation() : nil
        // The default 1 s cursor-hide watchdog is too short for menu
        // bar item moves, and the budget they can burn has grown: every
        // attempt spends its whole timeout four times over (two event
        // posts, two response waits), budgets escalate to the merged
        // ceiling of one second per operation, and a failed attempt posts
        // one more fallback at a fixed 100 ms. At the ceiling that is
        // roughly 32 s for eight attempts — far past the old flat 10 s,
        // whose comment still assumed "8 × ~500 ms". When the watchdog
        // fires partway through, the cursor is force-shown at the
        // synthetic event's last cursorPosition (mid-display, per the
        // offscreen-target override below in postMoveEvents) and the user
        // sees a brief cursor flash. The floor stays at 10 s so ordinary
        // moves keep their safety net against genuinely stuck states.
        if options.hideCursorAcrossAttempts {
            MouseHelpers.hideCursor(
                watchdogTimeout: options.watchdogTimeout ?? Self.cursorHideWatchdogTimeout(
                    maxAttempts: max(1, options.maxMoveAttempts)
                )
            )
        }
        defer {
            if let mouseLocation {
                MouseHelpers.restoreCursorPosition(to: mouseLocation)
                MouseHelpers.showCursor()
            }
        }

        // Tracks whether any postMoveEvents attempt produced observable
        // displacement. Only consulted on retries when the item being
        // moved is a zero-width control item (section divider), where
        // a position match can coincide with bounds drifting onto the
        // target externally; ordinary items skip this gate.
        var anyMoveEventsSucceeded = false

        // Baseline for the stale-plan check in the retry path. The destination
        // was chosen against the bar as it looked when this move was planned;
        // if the target itself travels a long way while we are dragging, the
        // plan describes an arrangement that no longer exists.
        let plannedTargetBounds = try? await getCurrentBounds(for: destination.targetItem)

        // Where the target has sat at the end of each failed attempt. A
        // single nudge is expected; a run of them in one direction is the
        // move pushing its own anchor. See `targetIsRetreating`.
        var targetMinXHistory: [CGFloat] = plannedTargetBounds.map { [$0.minX] } ?? []

        let maxAttempts = max(1, options.maxMoveAttempts)
        for n in 1 ... maxAttempts {
            var attemptMouseLocation: CGPoint?
            defer {
                if let attemptMouseLocation {
                    MouseHelpers.restoreCursorPosition(to: attemptMouseLocation)
                    MouseHelpers.showCursor()
                }
            }
            guard !Task.isCancelled else {
                MenuBarItemManager.diagLog.debug("move: cancelled before attempt \(n) for \(item.logString)")
                throw EventError.cannotComplete
            }
            guard options.shouldProceed?() ?? true else {
                MenuBarItemManager.diagLog.debug("move: superseded before attempt \(n) for \(item.logString)")
                throw EventError.moveSuperseded(item)
            }
            do {
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    // On the first iteration trust the position match
                    // unconditionally. On retries, the only case where the
                    // match can be a coincidence is when the item being
                    // moved is itself a zero-width control item; gate
                    // those on observed displacement, accept all others.
                    if n == 1 || anyMoveEventsSucceeded || !item.isControlItem {
                        MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
                        return
                    }
                    MenuBarItemManager.diagLog.debug(
                        "Position match without observable displacement on attempt \(n); treating as false positive on a zero-width control item and retrying"
                    )
                }
                if !options.hideCursorAcrossAttempts {
                    attemptMouseLocation = try getMouseLocation()
                    MouseHelpers.hideCursor(watchdogTimeout: options.watchdogTimeout ?? .seconds(2))
                }
                let attemptTimeout = try await postMoveEvents(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID,
                    warpCursorAfter: false // move() owns the single warp in its defer
                )
                // postMoveEvents only returns without throwing when both
                // waitForMoveEventResponse calls observed origin changes,
                // i.e. our drag actually displaced the item.
                anyMoveEventsSucceeded = true
                // Verify the item actually reached the correct position.
                let landedOnDestination = try await itemHasCorrectPosition(
                    item: item,
                    for: destination,
                    on: resolvedDisplayID
                )
                // `postMoveEvents` only observes displacement. Let this
                // single post-event landing check decide whether the next
                // attempt earns a shorter budget or keeps it unchanged;
                // querying Window Server in both places made misses look like
                // successful moves (#889).
                updateMoveOperationTimeout(
                    Self.nextMoveOperationTimeout(
                        after: attemptTimeout,
                        outcome: landedOnDestination ? .landed : .displacedWithoutLanding
                    ),
                    for: item
                )
                if landedOnDestination {
                    // Logged at info so the warm-up attempt cost can be read
                    // straight off a field log: grep "Move landed" and compare
                    // the attempt counts.
                    MenuBarItemManager.diagLog.info(
                        "Move landed: \(item.logString) after \(n) attempt(s)"
                    )
                    MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded and verified, finished with move")
                    failureLedger.recordSuccess(for: item)
                    // Validate that item didn't get stuck when moving to hidden section
                    await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
                    return
                }
                // Retrying against a target that has already moved re-plans
                // each attempt against different geometry and drags the item
                // somewhere new every time, which is what leaves a failed
                // batch with a fresh partial arrangement on every pass (#900).
                // Stop instead and let the next cache tick re-plan against a
                // settled bar.
                let currentTargetBounds = try? await getCurrentBounds(for: destination.targetItem)
                if let currentTargetBounds {
                    targetMinXHistory.append(currentTargetBounds.minX)
                }
                if let plannedTargetBounds,
                   let currentTargetBounds,
                   Self.destinationIsStale(
                       plannedTargetMinX: plannedTargetBounds.minX,
                       currentTargetMinX: currentTargetBounds.minX,
                       displayWidth: CGDisplayBounds(resolvedDisplayID).width
                   )
                {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Attempt \(n): \(destination.targetItem.logString) moved from \
                        minX=\(plannedTargetBounds.minX) to minX=\(currentTargetBounds.minX) \
                        during the drag, abandoning the stale move
                        """
                    )
                    throw EventError.staleDestination(item)
                }
                // Small steps that never trip the stale threshold still walk
                // the anchor across the bar if they all go the same way, and
                // when the anchor is one of Thaw's dividers that ends in a
                // zero-width hidden section (#924, #927). Stop and let the
                // next cache tick re-plan against a settled bar.
                if Self.targetIsRetreating(recentTargetMinX: targetMinXHistory) {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Attempt \(n): \(destination.targetItem.logString) has retreated on every \
                        recent attempt (minX \(targetMinXHistory.map { String(format: "%.0f", $0) }.joined(separator: " → "))) \
                        while \(item.logString) did not land; abandoning rather than pushing it further
                        """
                    )
                    throw EventError.staleDestination(item)
                }
                MenuBarItemManager.diagLog.debug("Attempt \(n) events succeeded but item not at destination, retrying")
                if n < maxAttempts {
                    guard options.shouldProceed?() ?? true else {
                        throw EventError.moveSuperseded(item)
                    }
                    try await waitForMoveOperationBuffer()
                    continue
                }
            } catch {
                // missingItemBounds is definitive: getCurrentBounds already
                // refreshed the on-screen items and re-matched by tag before
                // throwing, so the item's window is genuinely gone (transient
                // Control Center item vanished, owning app quit). Retrying
                // just warps the hidden cursor into the menu bar once per
                // remaining attempt for an item that cannot be moved (#736).
                if case EventError.missingItemBounds = error {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(item.logString) no longer reports bounds, aborting move"
                    )
                    throw error
                }
                // Also definitive for the duration of this call: a hung owner
                // will not start pumping its event loop within the few hundred
                // milliseconds between attempts, so the remaining attempts
                // would only re-pay the semaphore wait. Callers retry the item
                // on a later cache tick, by which point it may have recovered.
                if case EventError.ownerUnresponsive = error {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(item.logString) owner is unresponsive, aborting move"
                    )
                    failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    throw error
                }
                // Raised by the stale-plan check above, which has already
                // logged. Retrying is precisely what it exists to prevent, and
                // the item's owner did nothing wrong, so no failure is filed
                // against it.
                if case EventError.staleDestination = error {
                    throw error
                }
                if case EventError.moveSuperseded = error {
                    throw error
                }
                if case EventError.inputPauseTimedOut = error {
                    throw error
                }
                // An owner with a standing record of ignoring synthetic events
                // gets no further attempts once it fails this way again. This
                // is deliberately narrower than capping maxAttempts up front:
                // the loop also retries when the owner *did* respond but the
                // item did not land, which is a different failure and still
                // deserves its full budget. Capping up front would strip those
                // retries too, and since the move would then fail, the item
                // could never earn the success that clears its record.
                if let error = error as? EventError,
                   error.indicatesUnresponsiveOwner,
                   failureLedger.isUnresponsive(item)
                {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(item.logString) failed the way it always does, aborting move"
                    )
                    failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    throw error
                }
                MenuBarItemManager.diagLog.debug("Attempt \(n) failed: \(error)")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
                if let error = error as? EventError {
                    if error.indicatesUnresponsiveOwner {
                        failureLedger.recordFailure(for: item, kind: .unresponsiveOwner)
                    }
                    throw error
                }
                MenuBarItemManager.diagLog.warning("move: final attempt for \(item.logString) failed with non-EventError: \(error)")
                throw EventError.cannotComplete
            }
        }

        // All attempts exhausted without confirmed position. Run the stuck-item
        // validator first (recovers x=-1 blocks), then throw so callers know
        // the item did not reach the destination.
        await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
        MenuBarItemManager.diagLog.error("move: all \(maxAttempts) attempt(s) exhausted without verifying \(item.logString) reached \(destination.logString)")
        throw EventError.cannotComplete
    }
}
