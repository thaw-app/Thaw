//
//  MenuBarItemManager+MoveEvents.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics
import os.lock

// MARK: - Move Events

extension MenuBarItemManager {
    /// What one round of move events observed, beyond the timeout budget the
    /// next round inherits.
    nonisolated struct MoveEventsOutcome {
        var timeout: Duration
        var revertedToStart: Bool
        var strategy: MoveStrategy
    }

    /// Pure construction of a faithful, horizontal command-drag gesture.
    nonisolated enum MoveGesture {
        struct Step: Equatable {
            let subtype: MenuBarItemEventType.MoveSubtype
            let point: CGPoint
        }

        static func faithfulDrag(start: CGPoint, end: CGPoint, intermediateSteps: Int) -> [Step] {
            let steps = max(1, intermediateSteps)
            var result = [Step(subtype: .mouseDown, point: start)]
            for index in 1 ... steps {
                let t = CGFloat(index) / CGFloat(steps + 1)
                result.append(Step(
                    subtype: .mouseDragged,
                    point: CGPoint(
                        x: start.x + (end.x - start.x) * t,
                        y: start.y + (end.y - start.y) * t
                    )
                ))
            }
            result.append(Step(subtype: .mouseDragged, point: end))
            result.append(Step(subtype: .mouseUp, point: end))
            return result
        }
    }

    /// A teleport's mouse-down is stamped at the destination, even a parked one.
    nonisolated struct MoveEventLocations: Equatable {
        let press: CGPoint
        let release: CGPoint
    }

    static nonisolated func moveEventLocations(
        targetPoints: (start: CGPoint, end: CGPoint),
        faithfulDragStart: CGPoint?,
        sourceAnchoredStart: CGPoint? = nil
    ) -> MoveEventLocations {
        MoveEventLocations(
            press: faithfulDragStart ?? sourceAnchoredStart ?? targetPoints.start,
            release: targetPoints.end
        )
    }

    /// Waits for a menu bar item to respond to previously posted move events.
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
                let origin = try self.exactMoveBounds(for: item).origin
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

    /// Creates and posts the events that move a menu bar item to the destination.
    func postMoveEvents(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        budget: MoveTransactionBudget,
        warpCursorAfter: Bool = true,
        preferSourceAnchoredTeleport: Bool = false
    ) async throws -> MoveEventsOutcome {
        // Outside budget.run: its post-success deadline check can throw and leak
        // the permit for the life of the process.
        let semaphoreAllowance = try budget.timeout(for: .milliseconds(3500))
        do {
            try await eventSemaphore.wait(timeout: semaphoreAllowance)
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error(
                "eventSemaphore timed out while moving \(item.logString); preserving the transaction deadline"
            )
            throw EventError.cannotComplete
        }
        // The permit is held from here on, so the release is unconditional.
        defer {
            Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
        }

        // Admission can take seconds, so resolve both endpoints again.
        let initialEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: displayID
        )
        let initialDestination = initialEndpoints.destination(matching: destination)
        let initialGeometry = try validateMoveEndpointGeometry(
            item: initialEndpoints.source,
            target: initialEndpoints.target,
            snapshot: initialEndpoints.snapshot,
            on: displayID
        )
        let initialTargetPoints = getTargetPoints(
            forMoving: initialEndpoints.source,
            to: initialDestination,
            itemBounds: initialEndpoints.source.bounds,
            targetBounds: initialEndpoints.target.bounds,
            on: displayID
        )

        // tapCreateForPid silently makes an invalid Mach port for a dead PID, and
        // every scrombleEvent then burns the full 3.5 s budget.
        let eventPID = getEventPID(for: initialEndpoints.source)
        if kill(eventPID, 0) == -1, errno == ESRCH {
            MenuBarItemManager.diagLog.error("postMoveEvents: target PID \(eventPID) for \(item.logString) is dead; skipping move")
            throw EventError.cannotComplete
        }

        // A hung owner never acknowledges, burning 3.5 s with the semaphore held
        // and stalling every other move (e.g. Little Snitch). The caller's backoff retries.
        if Bridging.isProcessUnresponsive(eventPID) {
            MenuBarItemManager.diagLog.warning(
                "postMoveEvents: target PID \(eventPID) for \(item.logString) is unresponsive; skipping move"
            )
            throw EventError.ownerUnresponsive(item)
        }

        let initialStrategy: MoveStrategy
        switch transportDecision(
            item: initialEndpoints.source,
            itemBounds: initialEndpoints.source.bounds,
            targetPoint: initialTargetPoints.end,
            geometry: initialGeometry,
            on: displayID
        ) {
        case let .use(selected):
            initialStrategy = preferSourceAnchoredTeleport && selected != .faithfulDrag
                ? .sourceAnchoredTeleport
                : selected
        case .rejectUnsafePath:
            throw EventError.unsafeMovePath(initialEndpoints.source)
        }
        let initialDragPlan = initialStrategy == .faithfulDrag
            ? faithfulDragSteps(
                itemBounds: initialEndpoints.source.bounds,
                targetPoints: initialTargetPoints
            )
            : nil
        let initialEventLocations = Self.moveEventLocations(
            targetPoints: initialTargetPoints,
            faithfulDragStart: initialDragPlan?.first?.point,
            sourceAnchoredStart: initialStrategy == .sourceAnchoredTeleport
                ? CGPoint(x: initialEndpoints.source.bounds.midX, y: initialEndpoints.source.bounds.midY)
                : nil
        )

        // move() warps once after all attempts, so the cursor doesn't oscillate.
        let mouseLocation: CGPoint? = warpCursorAfter ? try getMouseLocation() : nil
        lastMoveOperationTimestamp = .now
        // No warp for offscreen targets: CGWarpMouseCursorPosition clamps under
        // the Apple menu and routes stray clicks there.
        let warpPoint = initialEventLocations.press
        let warpIsOnScreen = initialGeometry.target == .selectedDisplay
        if warpIsOnScreen {
            // Needed for delivery even during a bulk apply, hidden cursor or not.
            MouseHelpers.warpCursor(to: warpPoint)
        }
        // A bulk apply hides the cursor for the whole sequence; hiding per item
        // too visibly yanks it if the watchdog resets mid-sequence (#723).
        // Sampled once: a bulk apply starting mid-move would strand the cursor hidden.
        let ownsCursorVisibility = !isBulkApplyInProgress
        if ownsCursorVisibility {
            MouseHelpers.hideCursor()
        }
        // Redirecting an off-screen press made the item visibly jump to the center.
        defer {
            if let mouseLocation {
                MouseHelpers.restoreCursorPosition(to: mouseLocation)
            }
            if ownsCursorVisibility {
                MouseHelpers.showCursor()
            }
            lastMoveOperationTimestamp = .now
        }
        if warpIsOnScreen {
            try await budget.sleep(for: .milliseconds(20))
        }

        // Last await before the press; rebuild from fresh records.
        let endpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: displayID
        )
        let liveItem = endpoints.source
        let liveDestination = endpoints.destination(matching: destination)
        let geometry = try validateMoveEndpointGeometry(
            item: liveItem,
            target: endpoints.target,
            snapshot: endpoints.snapshot,
            on: displayID
        )
        let itemBounds = liveItem.bounds
        var itemOrigin = itemBounds.origin
        let targetPoints = getTargetPoints(
            forMoving: liveItem,
            to: liveDestination,
            itemBounds: itemBounds,
            targetBounds: endpoints.target.bounds,
            on: displayID
        )
        let strategy: MoveStrategy
        switch transportDecision(
            item: liveItem,
            itemBounds: itemBounds,
            targetPoint: targetPoints.end,
            geometry: geometry,
            on: displayID
        ) {
        case let .use(selected):
            strategy = preferSourceAnchoredTeleport && selected != .faithfulDrag
                ? .sourceAnchoredTeleport
                : selected
        case .rejectUnsafePath:
            MenuBarItemManager.diagLog.warning(
                "Move transport rejected unsafe or cross-display geometry for \(liveItem.logString)"
            )
            throw EventError.unsafeMovePath(liveItem)
        }
        let dragPlan = strategy == .faithfulDrag
            ? faithfulDragSteps(itemBounds: itemBounds, targetPoints: targetPoints)
            : nil
        let eventLocations = Self.moveEventLocations(
            targetPoints: targetPoints,
            faithfulDragStart: dragPlan?.first?.point,
            sourceAnchoredStart: strategy == .sourceAnchoredTeleport
                ? CGPoint(x: itemBounds.midX, y: itemBounds.midY)
                : nil
        )
        if warpIsOnScreen, eventLocations.press != warpPoint {
            MouseHelpers.warpCursor(to: eventLocations.press)
        }
        let source = try getEventSource()
        try permitLocalEvents()
        let releaseItem = strategy == .faithfulDrag || strategy == .sourceAnchoredTeleport
            ? liveItem
            : endpoints.target
        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: liveItem,
                source: source,
                type: .move(.mouseDown),
                location: eventLocations.press
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: releaseItem,
                source: source,
                type: .move(.mouseUp),
                location: eventLocations.release
            )
        else {
            throw EventError.eventCreationFailure(liveItem)
        }

        var timeout = getMoveOperationTimeout(for: liveItem)
        MenuBarItemManager.diagLog.debug("Move operation timeout: \(timeout)")
        MenuBarItemManager.diagLog.info(
            "Move strategy: \(strategy) for \(liveItem.logString); press at (\(eventLocations.press.x),\(eventLocations.press.y)), release at (\(eventLocations.release.x),\(eventLocations.release.y))"
        )
        let releaseGuard = try makePressReleaseGuard(
            for: liveItem,
            mouseUp: mouseUp,
            eventPID: eventPID,
            budget: budget
        )

        // The press may be down; the guard releases it if the attempt stalls.
        releaseGuard.arm()
        do {
            if let dragPlan {
                itemOrigin = try await postFaithfulDragSteps(
                    dragPlan,
                    drag: FaithfulDragContext(
                        item: liveItem,
                        source: source,
                        startOrigin: itemOrigin,
                        openingEvent: mouseDown,
                        releaseGuard: releaseGuard
                    ),
                    timeout: timeout,
                    destination: destination,
                    on: displayID,
                    budget: budget
                )
            } else {
                try await budget.run(maximum: timeout) { allowance in
                    try await scrombleEvent(
                        mouseDown,
                        item: liveItem,
                        timeout: allowance
                    )
                }
                itemOrigin = try await budget.run(maximum: timeout) { allowance in
                    try await waitForMoveEventResponse(
                        from: liveItem,
                        initialOrigin: itemOrigin,
                        timeout: allowance
                    )
                }

                // The press can reflow the target edge.
                let releaseEndpoints = try await resolveCurrentMoveEndpoints(
                    source: item,
                    destination: destination.targetItem,
                    on: displayID
                )
                _ = try validateMoveEndpointGeometry(
                    item: releaseEndpoints.source,
                    target: releaseEndpoints.target,
                    snapshot: releaseEndpoints.snapshot,
                    on: displayID
                )
                let releaseDestination = releaseEndpoints.destination(matching: destination)
                let releasePoints = getTargetPoints(
                    forMoving: releaseEndpoints.source,
                    to: releaseDestination,
                    itemBounds: releaseEndpoints.source.bounds,
                    targetBounds: releaseEndpoints.target.bounds,
                    on: displayID
                )
                let releaseLocation = strategy.keepsPlannedReleasePoint(
                    targetDisposition: geometry.target
                ) ? eventLocations.release : releasePoints.end
                if releaseLocation != releasePoints.end {
                    MenuBarItemManager.diagLog.debug(
                        "Parked release kept planned point \(releaseLocation.x) instead of reflowed \(releasePoints.end.x)"
                    )
                }
                let liveReleaseItem = strategy == .sourceAnchoredTeleport
                    ? releaseEndpoints.source
                    : releaseEndpoints.target
                guard let liveMouseUp = CGEvent.menuBarItemEvent(
                    item: liveReleaseItem,
                    source: source,
                    type: .move(.mouseUp),
                    location: releaseLocation
                ) else {
                    throw EventError.eventCreationFailure(releaseEndpoints.source)
                }
                try await budget.run(maximum: timeout, repeating: 2) { allowance in
                    try await scrombleEvent(
                        liveMouseUp,
                        item: releaseEndpoints.source,
                        timeout: allowance,
                        repeating: 2 // Double mouse up prevents invalid item state.
                    )
                }
                releaseGuard.recordReleaseAttempt(delivered: true)
                itemOrigin = try await budget.run(maximum: timeout) { allowance in
                    try await waitForMoveEventResponse(
                        from: releaseEndpoints.source,
                        initialOrigin: itemOrigin,
                        timeout: allowance
                    )
                }
            }
        } catch {
            let attemptError = error
            if releaseGuard.state == .armed, budget.elapsed < budget.limit {
                do {
                    MenuBarItemManager.diagLog.warning("Move events failed, posting fallback")
                    try await budget.run(maximum: .milliseconds(100), repeating: 2) { allowance in
                        try await scrombleEvent(
                            mouseUp,
                            item: liveItem,
                            timeout: allowance,
                            repeating: 2 // Double mouse up prevents invalid item state.
                        )
                    }
                    releaseGuard.recordReleaseAttempt(delivered: true)
                } catch let fallbackError {
                    // The guard stays armed as the final release path.
                    MenuBarItemManager.diagLog.error("Fallback failed with error: \(fallbackError)")
                }
            }
            timeout = Self.nextMoveOperationTimeout(after: timeout, outcome: .ownerDidNotRespond)
            updateMoveOperationTimeout(timeout, for: liveItem)
            if releaseGuard.didFire || budget.elapsed >= budget.limit {
                throw EventError.moveTimedOut(item)
            }
            throw attemptError
        }
        guard !releaseGuard.didFire else {
            throw EventError.moveTimedOut(item)
        }
        let revertedToStart = itemOrigin == itemBounds.origin
        if revertedToStart {
            MenuBarItemManager.diagLog.debug(
                "Move events (\(strategy)) left \(liveItem.logString) at its starting origin (\(itemOrigin.x),\(itemOrigin.y))"
            )
        }
        return MoveEventsOutcome(
            timeout: timeout,
            revertedToStart: revertedToStart,
            strategy: strategy
        )
    }

    /// Both endpoints are already proven to be on one display, in one notch-safe segment.
    private func faithfulDragSteps(
        itemBounds: CGRect,
        targetPoints: (start: CGPoint, end: CGPoint)
    ) -> [MoveGesture.Step] {
        let barY = itemBounds.minY
        return MoveGesture.faithfulDrag(
            start: CGPoint(x: itemBounds.midX, y: barY),
            end: CGPoint(x: targetPoints.end.x, y: barY),
            intermediateSteps: 3
        )
    }

    /// The fixed inputs of one faithful drag, set up before its first step.
    private struct FaithfulDragContext {
        let item: MenuBarItem
        let source: CGEventSource
        let startOrigin: CGPoint
        /// The already-built mouse down that opens the drag.
        let openingEvent: CGEvent
        let releaseGuard: PressReleaseGuard
    }

    /// Always releases on the bar before propagating a failure.
    private func postFaithfulDragSteps(
        _ steps: [MoveGesture.Step],
        drag: FaithfulDragContext,
        timeout: Duration,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        budget: MoveTransactionBudget
    ) async throws -> CGPoint {
        let item = drag.item
        let source = drag.source
        let startOrigin = drag.startOrigin
        let openingEvent = drag.openingEvent
        let releaseGuard = drag.releaseGuard
        guard steps.last?.subtype == .mouseUp else {
            throw EventError.eventCreationFailure(item)
        }
        let dragSteps = steps.dropLast()

        var itemOrigin = startOrigin
        var responseItem = item
        for (index, step) in dragSteps.enumerated() {
            let liveItem: MenuBarItem
            let event: CGEvent
            if index == 0 {
                guard step.subtype == .mouseDown else {
                    throw EventError.eventCreationFailure(item)
                }
                liveItem = item
                event = openingEvent
            } else {
                let endpoints = try await resolveCurrentMoveEndpoints(
                    source: item,
                    destination: destination.targetItem,
                    on: displayID
                )
                _ = try validateMoveEndpointGeometry(
                    item: endpoints.source,
                    target: endpoints.target,
                    snapshot: endpoints.snapshot,
                    on: displayID
                )
                liveItem = endpoints.source
                guard let liveEvent = CGEvent.menuBarItemEvent(
                    item: liveItem,
                    source: source,
                    type: .move(step.subtype),
                    location: step.point
                ) else {
                    throw EventError.eventCreationFailure(liveItem)
                }
                event = liveEvent
            }
            try await budget.run(maximum: timeout) { allowance in
                try await scrombleEvent(event, item: liveItem, timeout: allowance)
            }
            responseItem = liveItem
            if step.subtype == .mouseDragged {
                try await budget.sleep(for: .milliseconds(8))
            }
        }
        itemOrigin = try await budget.run(maximum: timeout) { allowance in
            try await waitForMoveEventResponse(
                from: responseItem,
                initialOrigin: startOrigin,
                timeout: allowance
            )
        }

        // Reflow can move the anchor while the button is held.
        let releaseEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: displayID
        )
        _ = try validateMoveEndpointGeometry(
            item: releaseEndpoints.source,
            target: releaseEndpoints.target,
            snapshot: releaseEndpoints.snapshot,
            on: displayID
        )
        let releaseDestination = releaseEndpoints.destination(matching: destination)
        let releasePoints = getTargetPoints(
            forMoving: releaseEndpoints.source,
            to: releaseDestination,
            itemBounds: releaseEndpoints.source.bounds,
            targetBounds: releaseEndpoints.target.bounds,
            on: displayID
        )
        let releasePoint = CGPoint(
            x: releasePoints.end.x,
            y: releaseEndpoints.source.bounds.minY
        )
        guard let releaseEvent = CGEvent.menuBarItemEvent(
            item: releaseEndpoints.source,
            source: source,
            type: .move(.mouseUp),
            location: releasePoint
        ) else {
            throw EventError.eventCreationFailure(releaseEndpoints.source)
        }
        try await budget.run(maximum: timeout, repeating: 2) { allowance in
            try await scrombleEvent(
                releaseEvent,
                item: releaseEndpoints.source,
                timeout: allowance,
                repeating: 2
            )
        }
        releaseGuard.recordReleaseAttempt(delivered: true)

        // A revert produces no origin change to await, so settle briefly and re-read.
        try await budget.sleep(for: .milliseconds(30))
        let restingEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: displayID
        )
        itemOrigin = restingEndpoints.source.bounds.origin
        return itemOrigin
    }

    /// How long a synthetic press may remain down before its guard releases it.
    static nonisolated func pressReleaseDeadline(for timeout: Duration) -> Duration {
        (timeout * 6).clamped(min: .milliseconds(1500), max: .seconds(3))
    }

    /// @unchecked is safe: CGEvent posting is thread-safe and the event is
    /// never mutated after arming.
    nonisolated struct PressReleaseEvents: @unchecked Sendable {
        let mouseUp: CGEvent
        let pid: pid_t
    }

    /// Releases a stalled synthetic press. A dangling press turns the user's next
    /// click into the end of a drag, which can even remove the status item.
    final nonisolated class PressReleaseGuard: Sendable {
        typealias Scheduler = @Sendable (
            _ deadline: Duration,
            _ action: @escaping @Sendable () -> Void
        ) -> Void

        enum State: Equatable {
            case idle
            case armed
            case releaseConfirmed
            case fired
        }

        private nonisolated struct Status {
            var state = State.idle
        }

        private let status = OSAllocatedUnfairLock(initialState: Status())
        private let deadline: Duration
        private let item: MenuBarItem
        private let scheduler: Scheduler
        private let postSafetyRelease: @Sendable () -> Void

        init(deadline: Duration, events: PressReleaseEvents, item: MenuBarItem) {
            self.deadline = deadline
            self.item = item
            scheduler = { deadline, action in
                let milliseconds = max(1, Int(deadline.milliseconds))
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + .milliseconds(milliseconds),
                    execute: action
                )
            }
            postSafetyRelease = {
                events.mouseUp.post(to: .sessionEventTap)
                events.mouseUp.post(to: .pid(events.pid))
            }
        }

        /// Test seam: drives the watchdog without sleeping or posting events.
        init(
            deadline: Duration,
            item: MenuBarItem,
            scheduler: @escaping Scheduler,
            postSafetyRelease: @escaping @Sendable () -> Void
        ) {
            self.deadline = deadline
            self.item = item
            self.scheduler = scheduler
            self.postSafetyRelease = postSafetyRelease
        }

        func arm() {
            let armed = status.withLock { status -> Bool in
                guard status.state == .idle else {
                    return false
                }
                status.state = .armed
                return true
            }
            guard armed else {
                return
            }
            let status = status
            let item = item
            let milliseconds = max(1, Int(deadline.milliseconds))
            let postSafetyRelease = postSafetyRelease
            scheduler(deadline) {
                let fires = status.withLock { status -> Bool in
                    guard status.state == .armed else {
                        return false
                    }
                    status.state = .fired
                    return true
                }
                guard fires else {
                    return
                }
                MenuBarItemManager.diagLog.warning(
                    "Press on \(item.logString) outlived its \(milliseconds) ms deadline; releasing it"
                )
                postSafetyRelease()
            }
        }

        var didFire: Bool {
            status.withLock { $0.state == .fired }
        }

        var state: State {
            status.withLock(\.state)
        }

        /// Only an acknowledged mouse-up disarms the safety post.
        func recordReleaseAttempt(delivered: Bool) {
            guard delivered else {
                return
            }
            status.withLock { status in
                guard status.state == .armed else {
                    return
                }
                status.state = .releaseConfirmed
            }
        }
    }

    private func makePressReleaseGuard(
        for item: MenuBarItem,
        mouseUp: CGEvent,
        eventPID: pid_t,
        budget: MoveTransactionBudget
    ) throws -> PressReleaseGuard {
        return try PressReleaseGuard(
            deadline: min(
                Self.pressReleaseDeadline(for: getMoveOperationTimeout(for: item)),
                budget.remaining()
            ),
            events: PressReleaseEvents(mouseUp: mouseUp, pid: eventPID),
            item: item
        )
    }
}
