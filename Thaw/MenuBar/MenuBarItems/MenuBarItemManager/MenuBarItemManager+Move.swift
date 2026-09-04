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
import os.lock

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

        /// Rebuilds the same logical side against a freshly enumerated
        /// destination window. The plan retains its original identity while
        /// event construction uses the newest record for that identity.
        func replacingTarget(with item: MenuBarItem) -> Self {
            switch self {
            case .leftOfItem:
                .leftOfItem(item)
            case .rightOfItem:
                .rightOfItem(item)
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
            // The chevron was excluded once, on the theory that it is a
            // control item but not a section boundary, so a drop on its
            // edge resolves no ambiguity worth paying for. #1035 kills that
            // theory as well. TemporaryShow anchors its reveal on the
            // chevron with .leftOfItem, and the reporter's log has attempt 2
            // planning targetMinX=837 and then finding the item at
            // itemMinX=863 — landed to the chevron's right, the same
            // wrong-side drop #923 described, caught by the same ordinal
            // check. What makes a drop point ambiguous is that it is an
            // item's own edge; whether that item happens to divide two
            // sections has nothing to do with it.
            let targetIsControlItem = targetItem.tag == .hiddenControlItem
                || targetItem.tag == .alwaysHiddenControlItem
                || targetItem.tag == .visibleControlItem
            let sectionBias: CGFloat = targetIsControlItem ? 1 : 0
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

    /// The event transport selected for one attempt. Parked and cross-notch
    /// teleports are named separately so an unsafe faithful plan can never
    /// silently collapse into the legacy press-at-destination path.
    nonisolated enum MoveStrategy: Equatable, CustomStringConvertible {
        case teleport
        case faithfulDrag
        case parkedTeleport
        case crossNotchTeleport

        var description: String {
            switch self {
            case .teleport: "teleport"
            case .faithfulDrag: "faithfulDrag"
            case .parkedTeleport: "parkedTeleport"
            case .crossNotchTeleport: "crossNotchTeleport"
            }
        }
    }

    /// Whether a horizontal on-bar gesture can stay inside one safe segment.
    nonisolated enum HorizontalPathDisposition: Equatable {
        case sameSafeSegment
        case crossesNotch
        case invalidEndpoint
    }

    /// The strict transport decision, including a refusal to post events.
    nonisolated enum MoveTransportDecision: Equatable {
        case use(MoveStrategy)
        case rejectUnsafePath
    }

    /// Logical placement of a move endpoint relative to the selected menu-bar
    /// lane. Screen coordinates alone cannot identify parked items because a
    /// physical display may legitimately sit to the selected display's left.
    nonisolated enum MoveEndpointDisposition: Equatable {
        case selectedDisplay
        case parked
        case otherDisplay(CGDirectDisplayID)
        case invalid
    }

    nonisolated struct MoveDisplayGeometry: Equatable {
        let id: CGDirectDisplayID
        let bounds: CGRect
    }

    static nonisolated func moveEndpointDisposition(
        bounds: CGRect,
        isOnScreen: Bool,
        selectedDisplayID: CGDirectDisplayID,
        displays: [MoveDisplayGeometry],
        parkedLaneYRange: ClosedRange<CGFloat>?,
        controlDividerX: CGFloat?
    ) -> MoveEndpointDisposition {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if isOnScreen {
            guard let physicalDisplay = displays.first(where: { $0.bounds.contains(center) }) else {
                return .invalid
            }
            return physicalDisplay.id == selectedDisplayID
                ? .selectedDisplay
                : .otherDisplay(physicalDisplay.id)
        }

        guard
            let parkedLaneYRange,
            let controlDividerX,
            parkedLaneYRange.contains(bounds.midY),
            bounds.maxX <= controlDividerX
        else {
            return .invalid
        }
        return .parked
    }

    /// Signals that the absolute budget shared by an entire move transaction
    /// has been exhausted.
    nonisolated struct MoveDeadlineExceeded: Error, Equatable {}

    /// One absolute budget shared by admission, gate waiting, event transport,
    /// layout settling, and retries. Every nested wait receives only the time
    /// still available to the transaction.
    nonisolated struct MoveTransactionBudget {
        typealias Elapsed = @Sendable () -> Duration
        typealias Sleeper = @Sendable (Duration) async throws -> Void

        let limit: Duration
        private let elapsedProvider: Elapsed
        private let sleeper: Sleeper

        init(limit: Duration) {
            let startedAt = ContinuousClock.now
            self.init(
                limit: limit,
                elapsed: { startedAt.duration(to: .now) },
                sleeper: { try await Task.sleep(for: $0) }
            )
        }

        init(
            limit: Duration,
            elapsed: @escaping Elapsed,
            sleeper: @escaping Sleeper
        ) {
            self.limit = limit
            elapsedProvider = elapsed
            self.sleeper = sleeper
        }

        var elapsed: Duration {
            elapsedProvider()
        }

        func remaining() throws -> Duration {
            let value = limit - elapsed
            guard value > .zero else {
                throw MoveDeadlineExceeded()
            }
            return value
        }

        func timeout(for requested: Duration, repeating count: Int = 1) throws -> Duration {
            let repetitions = max(1, count)
            let value = try min(requested, remaining() / repetitions)
            guard value > .zero else {
                throw MoveDeadlineExceeded()
            }
            return value
        }

        func run<Value>(
            maximum: Duration,
            repeating count: Int = 1,
            operation: (Duration) async throws -> Value
        ) async throws -> Value {
            let allowance = try timeout(for: maximum, repeating: count)
            do {
                let value = try await operation(allowance)
                _ = try remaining()
                return value
            } catch {
                if elapsed >= limit {
                    throw MoveDeadlineExceeded()
                }
                throw error
            }
        }

        func sleep(for duration: Duration) async throws {
            let available = try remaining()
            guard available >= duration else {
                try await sleeper(available)
                throw MoveDeadlineExceeded()
            }
            try await sleeper(duration)
            _ = try remaining()
        }
    }

    /// Classifies a horizontal menu-bar path without consulting AppKit.
    static nonisolated func horizontalPathDisposition(
        sourceX: CGFloat,
        destinationX: CGFloat,
        displayXRange: ClosedRange<CGFloat>,
        reservedNotchXRange: ClosedRange<CGFloat>?
    ) -> HorizontalPathDisposition {
        guard displayXRange.contains(sourceX), displayXRange.contains(destinationX) else {
            return .invalidEndpoint
        }
        guard let notch = reservedNotchXRange else {
            return .sameSafeSegment
        }
        guard !notch.contains(sourceX), !notch.contains(destinationX) else {
            return .invalidEndpoint
        }
        let crosses = (sourceX < notch.lowerBound && destinationX > notch.upperBound)
            || (destinationX < notch.lowerBound && sourceX > notch.upperBound)
        return crosses ? .crossesNotch : .sameSafeSegment
    }

    /// Selects a transport from explicit display membership and path safety.
    /// A `nil` endpoint display means WindowServer has parked it off-screen;
    /// a non-selected display means the plan is stale or cross-display and is
    /// rejected instead of being teleported.
    static nonisolated func strictTransportDecision(
        faithfulDragEnabled: Bool,
        itemIsControlItem: Bool,
        sourceDisplayID: CGDirectDisplayID?,
        destinationDisplayID: CGDirectDisplayID?,
        selectedDisplayID: CGDirectDisplayID,
        horizontalPath: HorizontalPathDisposition
    ) -> MoveTransportDecision {
        if let sourceDisplayID, sourceDisplayID != selectedDisplayID {
            return .rejectUnsafePath
        }
        if let destinationDisplayID, destinationDisplayID != selectedDisplayID {
            return .rejectUnsafePath
        }
        if sourceDisplayID == nil || destinationDisplayID == nil {
            return .use(.parkedTeleport)
        }
        return switch horizontalPath {
        case .invalidEndpoint:
            .rejectUnsafePath
        case .crossesNotch:
            .use(.crossNotchTeleport)
        case .sameSafeSegment:
            .use(faithfulDragEnabled && !itemIsControlItem ? .faithfulDrag : .teleport)
        }
    }

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

    /// Final coordinates used to create the opening and closing events for a
    /// move. A teleport has no visible intermediate press: its mouse-down is
    /// stamped directly at the destination, including when that destination
    /// is parked off-screen.
    nonisolated struct MoveEventLocations: Equatable {
        let press: CGPoint
        let release: CGPoint
    }

    static nonisolated func moveEventLocations(
        targetPoints: (start: CGPoint, end: CGPoint),
        faithfulDragStart: CGPoint?
    ) -> MoveEventLocations {
        MoveEventLocations(
            press: faithfulDragStart ?? targetPoints.start,
            release: targetPoints.end
        )
    }

    /// Exact ordinal positions from one WindowServer snapshot. Verification
    /// never falls back to a same-tag window, because a relaunched or cloned
    /// item is not the endpoint whose move acquired the gate.
    nonisolated struct MoveEndpointIndices: Equatable {
        let source: Int
        let destination: Int
    }

    static nonisolated func moveEndpointIndices(
        in items: [MenuBarItem],
        sourceWindowID: CGWindowID,
        destinationWindowID: CGWindowID
    ) -> MoveEndpointIndices? {
        guard sourceWindowID != destinationWindowID else {
            return nil
        }
        guard
            items.count(where: { $0.windowID == sourceWindowID }) == 1,
            items.count(where: { $0.windowID == destinationWindowID }) == 1,
            let sourceItem = items.first(where: { $0.windowID == sourceWindowID }),
            let destinationItem = items.first(where: { $0.windowID == destinationWindowID })
        else {
            return nil
        }

        // An equal-X endpoint is mid-reflow or zero-width-overlapped. Giving
        // it an arbitrary order by enumeration or window ID could certify the
        // wrong side, so wait for a later settled snapshot instead.
        guard
            items.count(where: { $0.bounds.minX == sourceItem.bounds.minX }) == 1,
            items.count(where: { $0.bounds.minX == destinationItem.bounds.minX }) == 1
        else {
            return nil
        }

        let sorted = items.sorted {
            if $0.bounds.minX == $1.bounds.minX {
                return $0.windowID < $1.windowID
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        guard
            let source = sorted.firstIndex(where: { $0.windowID == sourceWindowID }),
            let destination = sorted.firstIndex(where: { $0.windowID == destinationWindowID })
        else {
            return nil
        }
        return MoveEndpointIndices(source: source, destination: destination)
    }

    /// Whether a freshly enumerated endpoint is still the exact item that was
    /// planned before the move waited for the app-wide gate.
    static nonisolated func moveEndpointIsCurrent(
        _ candidate: MenuBarItem,
        expected: MenuBarItem
    ) -> Bool {
        candidate.windowID == expected.windowID
            && candidate.ownerPID == expected.ownerPID
            && candidate.sourcePID == expected.sourcePID
            && candidate.tag == expected.tag
    }

    /// Fresh source and destination records from one coherent WindowServer
    /// snapshot.
    nonisolated struct CurrentMoveEndpoints: Equatable {
        let source: MenuBarItem
        let target: MenuBarItem
        let snapshot: [MenuBarItem]

        func destination(matching planned: MoveDestination) -> MoveDestination {
            planned.replacingTarget(with: target)
        }
    }

    nonisolated enum MoveEndpointResolutionError: Error, Equatable {
        case missingSource
        case missingDestination
        case recycledSource
        case recycledDestination
    }

    static nonisolated func currentMoveEndpoints(
        in items: [MenuBarItem],
        expectedSource: MenuBarItem,
        expectedDestination: MenuBarItem
    ) -> Result<CurrentMoveEndpoints, MoveEndpointResolutionError> {
        func resolve(
            _ expected: MenuBarItem,
            missing: MoveEndpointResolutionError,
            recycled: MoveEndpointResolutionError
        ) -> Result<MenuBarItem, MoveEndpointResolutionError> {
            let sameID = items.filter { $0.windowID == expected.windowID }
            guard !sameID.isEmpty else {
                return .failure(missing)
            }
            let exact = sameID.filter { moveEndpointIsCurrent($0, expected: expected) }
            guard exact.count == 1 else {
                return .failure(recycled)
            }
            return .success(exact[0])
        }

        let source: MenuBarItem
        switch resolve(expectedSource, missing: .missingSource, recycled: .recycledSource) {
        case let .success(item):
            source = item
        case let .failure(error):
            return .failure(error)
        }

        let target: MenuBarItem
        switch resolve(expectedDestination, missing: .missingDestination, recycled: .recycledDestination) {
        case let .success(item):
            target = item
        case let .failure(error):
            return .failure(error)
        }

        guard source.windowID != target.windowID else {
            return .failure(.recycledDestination)
        }
        return .success(CurrentMoveEndpoints(source: source, target: target, snapshot: items))
    }

    static nonisolated func endpointsHaveCorrectPosition(
        _ endpoints: CurrentMoveEndpoints,
        for destination: MoveDestination
    ) -> Bool {
        guard let indices = moveEndpointIndices(
            in: endpoints.snapshot,
            sourceWindowID: endpoints.source.windowID,
            destinationWindowID: endpoints.target.windowID
        ) else {
            return false
        }
        return switch destination {
        case .leftOfItem:
            indices.source == indices.destination - 1
        case .rightOfItem:
            indices.source == indices.destination + 1
        }
    }

    /// Serializes complete move transactions app-wide. Serializing only event
    /// posts lets two independent retry loops undo each other between attempts.
    private static let moveGate = SimpleSemaphore(value: 1)

    /// A blocked-item recovery may call `move` while its parent still owns the
    /// gate; task-local ownership lets that nested move pass through safely.
    @TaskLocal private static var holdsMoveGate = false

    /// Nested recovery moves inherit their parent's absolute deadline rather
    /// than silently receiving another full transaction budget.
    @TaskLocal private static var currentMoveBudget: MoveTransactionBudget?

    private static let moveGateTimeout: Duration = .seconds(15)

    /// User activity can defer one move without retaining the app-wide move
    /// permit indefinitely.
    static nonisolated let moveInputPauseLimit: Duration = .seconds(2)

    /// Runs a caller's gate-owned completion hook before another move can enter.
    static func performMoveGateExitActions(
        didFinishWhileHoldingGate: (@MainActor () -> Void)?,
        releaseGate: () -> Void
    ) {
        didFinishWhileHoldingGate?()
        releaseGate()
    }

    /// Performs admission work before acquiring the app-wide move gate.
    /// Nested recovery moves already own the gate and enter directly.
    static func performWithMoveGate(
        timeout: Duration = moveGateTimeout,
        timeoutProvider: (@MainActor () throws -> Duration)? = nil,
        waitBeforeGate: @MainActor () async throws -> Void = {},
        didFinishWhileHoldingGate: (@MainActor () -> Void)? = nil,
        operation: @MainActor () async throws -> Void
    ) async throws {
        if holdsMoveGate {
            try await operation()
            return
        }

        try await waitBeforeGate()
        try await moveGate.wait(timeout: timeoutProvider?() ?? timeout)
        defer {
            performMoveGateExitActions(
                didFinishWhileHoldingGate: didFinishWhileHoldingGate,
                releaseGate: {
                    Task.detached { await moveGate.signal() }
                }
            )
        }
        try await $holdsMoveGate.withValue(true) {
            try await operation()
        }
    }

    /// Polls until two consecutive readings agree, or the bounded poll count
    /// is exhausted. The value and confirmation bit are returned separately
    /// so a caller never mistakes a last, still-changing sample for settled.
    static nonisolated func settledReading<Value: Equatable>(
        maxPolls: Int,
        read: () async -> Value,
        wait: () async -> Void
    ) async -> (value: Value, settled: Bool) {
        var previous = await read()
        var polls = 1
        while polls < maxPolls {
            await wait()
            let current = await read()
            polls += 1
            if current == previous {
                return (current, true)
            }
            previous = current
        }
        return (previous, false)
    }

    /// Waits for the exact source and destination windows to stop moving
    /// before judging their ordinal relationship. Control Center animates bar
    /// reflow after release, so an immediate read can reject a correct drop.
    nonisolated func waitForLayoutToSettle(
        item: MenuBarItem,
        target: MenuBarItem,
        interval: Duration = .milliseconds(25),
        maxPolls: Int = 24
    ) async {
        let outcome = await Self.settledReading(
            maxPolls: maxPolls,
            read: {
                [Bridging.getWindowBounds(for: item.windowID), Bridging.getWindowBounds(for: target.windowID)]
            },
            wait: { await self.eventSleep(for: interval) }
        )
        if !outcome.settled {
            MenuBarItemManager.diagLog.debug(
                "Layout still changing after \(maxPolls) polls while moving \(item.logString) relative to \(target.logString); verifying anyway"
            )
        }
    }

    /// Layout settling constrained by the transaction's absolute deadline.
    nonisolated func waitForLayoutToSettle(
        item: MenuBarItem,
        target: MenuBarItem,
        budget: MoveTransactionBudget,
        interval: Duration = .milliseconds(25),
        maxPolls: Int = 24
    ) async throws {
        var previous = [
            Bridging.getWindowBounds(for: item.windowID),
            Bridging.getWindowBounds(for: target.windowID),
        ]
        var polls = 1
        while polls < maxPolls {
            try await budget.sleep(for: interval)
            let current = [
                Bridging.getWindowBounds(for: item.windowID),
                Bridging.getWindowBounds(for: target.windowID),
            ]
            polls += 1
            if current == previous {
                return
            }
            previous = current
        }
        if maxPolls > 1 {
            MenuBarItemManager.diagLog.debug(
                "Layout still changing after \(maxPolls) polls while moving \(item.logString) relative to \(target.logString); verifying anyway"
            )
        }
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

    /// Reads geometry only from the exact WindowServer window selected by the
    /// move plan. A same-tag replacement may belong to a relaunch or clone and
    /// must be left for a fresh cache cycle to plan.
    private nonisolated func exactMoveBounds(
        for item: MenuBarItem,
        isDestination: Bool = false
    ) throws -> CGRect {
        guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
            if isDestination {
                throw EventError.missingDestinationBounds(item)
            }
            throw EventError.missingItemBounds(item)
        }
        return bounds
    }

    /// Re-enumerates both planned endpoints with source ownership resolved and
    /// returns fresh records from the same snapshot.
    private func resolveCurrentMoveEndpoints(
        source expectedSource: MenuBarItem,
        destination expectedDestination: MenuBarItem,
        on displayID: CGDirectDisplayID
    ) async throws -> CurrentMoveEndpoints {
        let items = await MenuBarItem.getMenuBarItems(
            on: displayID,
            option: .activeSpace,
            resolveSourcePID: true
        ).filter { !$0.isSystemClone }
        switch Self.currentMoveEndpoints(
            in: items,
            expectedSource: expectedSource,
            expectedDestination: expectedDestination
        ) {
        case let .success(endpoints):
            return endpoints
        case .failure(.missingSource):
            throw EventError.missingItemBounds(expectedSource)
        case .failure(.missingDestination):
            throw EventError.missingDestinationBounds(expectedDestination)
        case .failure(.recycledDestination):
            throw EventError.staleDestination(expectedSource)
        case .failure(.recycledSource):
            throw EventError.moveSuperseded(expectedSource)
        }
    }

    /// Validates both endpoint locations and distinguishes a genuinely parked
    /// status item from a window belonging to a physical display on the left.
    private func validateMoveEndpointGeometry(
        item: MenuBarItem,
        target: MenuBarItem,
        snapshot: [MenuBarItem],
        on displayID: CGDirectDisplayID
    ) throws -> (source: MoveEndpointDisposition, target: MoveEndpointDisposition) {
        let selectedBounds = CGDisplayBounds(displayID)
        let displays = NSScreen.screens.map {
            MoveDisplayGeometry(id: $0.displayID, bounds: CGDisplayBounds($0.displayID))
        }
        let dividers = snapshot.filter {
            ($0.tag == .hiddenControlItem || $0.tag == .alwaysHiddenControlItem)
                && (selectedBounds.minX ... selectedBounds.maxX).contains($0.bounds.maxX)
                && (selectedBounds.minY ... selectedBounds.maxY).contains($0.bounds.midY)
        }
        let parkedLaneYRange: ClosedRange<CGFloat>? = if
            let minY = dividers.map(\.bounds.minY).min(),
            let maxY = dividers.map(\.bounds.maxY).max()
        {
            minY ... maxY
        } else {
            selectedBounds.minY ... (selectedBounds.minY + 64)
        }
        let dividerX = dividers.map(\.bounds.maxX).max() ?? selectedBounds.minX

        func disposition(for endpoint: MenuBarItem) throws -> MoveEndpointDisposition {
            let value = Self.moveEndpointDisposition(
                bounds: endpoint.bounds,
                isOnScreen: endpoint.isOnScreen,
                selectedDisplayID: displayID,
                displays: displays,
                parkedLaneYRange: parkedLaneYRange,
                controlDividerX: dividerX
            )
            switch value {
            case .selectedDisplay, .parked:
                return value
            case .otherDisplay, .invalid:
                MenuBarItemManager.diagLog.warning(
                    "Move rejected stale or cross-display endpoint geometry for \(endpoint.logString)"
                )
                throw EventError.staleDestination(item)
            }
        }
        return try (disposition(for: item), disposition(for: target))
    }

    private func transportDecision(
        item: MenuBarItem,
        itemBounds: CGRect,
        targetPoint: CGPoint,
        geometry: (source: MoveEndpointDisposition, target: MoveEndpointDisposition),
        on displayID: CGDirectDisplayID
    ) -> MoveTransportDecision {
        let displayBounds = CGDisplayBounds(displayID)
        let screen = NSScreen.screens.first { $0.displayID == displayID }
        let notchRange = screen?.frameOfNotch.map { notch in
            (notch.minX - 2) ... (notch.maxX + 2)
        }
        let path = Self.horizontalPathDisposition(
            sourceX: itemBounds.midX,
            destinationX: targetPoint.x,
            displayXRange: displayBounds.minX ... displayBounds.maxX,
            reservedNotchXRange: notchRange
        )
        return Self.strictTransportDecision(
            faithfulDragEnabled: faithfulDragMovesEnabled,
            itemIsControlItem: item.isControlItem,
            sourceDisplayID: geometry.source == .selectedDisplay ? displayID : nil,
            destinationDisplayID: geometry.target == .selectedDisplay ? displayID : nil,
            selectedDisplayID: displayID,
            horizontalPath: path
        )
    }

    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MoveDestination,
        itemBounds: CGRect,
        targetBounds: CGRect,
        on displayID: CGDirectDisplayID
    ) -> (start: CGPoint, end: CGPoint) {
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
    /// so they cannot drift apart mid-check. Both endpoints are matched by
    /// exact window ID; equal-X endpoints remain unverified rather than being
    /// assigned an arbitrary order while the bar is reflowing.
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
        let endpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: displayID
        )
        return Self.endpointsHaveCorrectPosition(endpoints, for: destination)
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
        budget: MoveTransactionBudget,
        warpCursorAfter: Bool = true
    ) async throws -> MoveEventsOutcome {
        var acquiredSemaphore = false
        do {
            try await budget.run(maximum: .milliseconds(3500)) { timeout in
                try await eventSemaphore.wait(timeout: timeout)
            }
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error(
                "eventSemaphore timed out while moving \(item.logString); preserving the transaction deadline"
            )
            throw EventError.cannotComplete
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        // Event-transport admission can take seconds. Resolve both exact
        // identities again before using any endpoint geometry.
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

        // Fast-fail if the target process is dead. CGEvent.tapCreateForPid
        // silently produces an invalid Mach port for dead PIDs, causing every
        // scrombleEvent to time out and burn the full 3.5 s semaphore budget.
        let eventPID = getEventPID(for: initialEndpoints.source)
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

        let initialStrategy: MoveStrategy
        switch transportDecision(
            item: initialEndpoints.source,
            itemBounds: initialEndpoints.source.bounds,
            targetPoint: initialTargetPoints.end,
            geometry: initialGeometry,
            on: displayID
        ) {
        case let .use(selected):
            initialStrategy = selected
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
            faithfulDragStart: initialDragPlan?.first?.point
        )

        // Capture mouse location only when this call owns the cursor warp.
        // When called from move(), the outer move() handles the single warp
        // at the end of all attempts so the cursor doesn't oscillate per attempt.
        let mouseLocation: CGPoint? = warpCursorAfter ? try getMouseLocation() : nil
        lastMoveOperationTimestamp = .now
        // Skip the warp when the target is offscreen (negative-X items in
        // hidden/always-hidden on notch displays). CGWarpMouseCursorPosition
        // clamps to the display's leftmost edge, which sits under the Apple
        // menu, and the resulting tracking events then route stray clicks
        // there. The 20ms eventSleep that follows the warp is only needed
        // when slow apps have to register the tracking events before the
        // mouseDown; irrelevant offscreen.
        let warpPoint = initialEventLocations.press
        let warpIsOnScreen = initialGeometry.target == .selectedDisplay
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
        // Keep an off-screen teleport's stamped press at the off-screen
        // destination. Redirecting it to the notch midpoint made the real
        // status-item window visibly jump to the center before the release.
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
        if warpIsOnScreen {
            try await budget.sleep(for: .milliseconds(20))
        }

        // The cursor-registration wait is the final intentional await before
        // the press. Re-resolve and construct the events from fresh records.
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
            strategy = selected
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
            faithfulDragStart: dragPlan?.first?.point
        )
        if warpIsOnScreen, eventLocations.press != warpPoint {
            MouseHelpers.warpCursor(to: eventLocations.press)
        }
        let source = try getEventSource()
        try permitLocalEvents()
        let releaseItem = strategy == .faithfulDrag ? liveItem : endpoints.target
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

        // From here the press may be down; a deadline guard posts a matching
        // release even if the async attempt stops making progress.
        releaseGuard.arm()
        do {
            if let dragPlan {
                itemOrigin = try await postFaithfulDragSteps(
                    dragPlan,
                    item: liveItem,
                    source: source,
                    startOrigin: itemOrigin,
                    timeout: timeout,
                    openingEvent: mouseDown,
                    releaseGuard: releaseGuard,
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

                // Reflow after the opening press can move the target edge.
                // Release against a freshly validated endpoint snapshot.
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
                guard let liveMouseUp = CGEvent.menuBarItemEvent(
                    item: releaseEndpoints.target,
                    source: source,
                    type: .move(.mouseUp),
                    location: releasePoints.end
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
                    // Keep the guard armed so its independent raw post remains
                    // the final release path.
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

    /// Builds a faithful drag on the item's own menu-bar row. The strict
    /// transport classifier has already proved both endpoints are on the
    /// selected display and in one notch-safe segment.
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

    /// Posts one coherent faithful drag, and always ends it with a release on
    /// the bar before propagating a failure.
    private func postFaithfulDragSteps(
        _ steps: [MoveGesture.Step],
        item: MenuBarItem,
        source: CGEventSource,
        startOrigin: CGPoint,
        timeout: Duration,
        openingEvent: CGEvent,
        releaseGuard: PressReleaseGuard,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        budget: MoveTransactionBudget
    ) async throws -> CGPoint {
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

        // Reflow can move the anchor while the button is held. Re-resolve and
        // validate the exact release edge instead of using the planned one.
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

        // A revert returns to the start and therefore cannot be awaited as an
        // origin change after release. Give the drop one short settling beat
        // and re-resolve the exact source before reading its resting origin.
        try await budget.sleep(for: .milliseconds(30))
        let restingEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: displayID
        )
        itemOrigin = restingEndpoints.source.bounds.origin
        return itemOrigin
    }

    private var faithfulDragMovesEnabled: Bool {
        (Defaults.object(forKey: .faithfulDragMoves) as? Bool) ?? Defaults.DefaultValue.faithfulDragMoves
    }

    /// Checks if a menu bar item is in a "blocked" state (positioned at x=-1 off-screen).
    /// Items in this state are stuck and cannot be interacted with normally.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try exactMoveBounds(for: item)
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
        /// Evaluated once the move transaction owns the gate, before any
        /// action is taken. Returning false supersedes a move that became
        /// stale while it was queued behind another move.
        var shouldBegin: (@MainActor () -> Bool)?
        /// Runs while the gate is still held, after the move finished but
        /// before another move may enter.
        var didFinishWhileHoldingGate: (@MainActor () -> Void)?
    }

    /// The whole move yields the gate before the cursor watchdog and queued
    /// callers give up, even when each individual attempt remains bounded.
    static nonisolated let moveDeadline: Duration = .seconds(8)

    /// How long a synthetic press may remain down before its guard releases it.
    static nonisolated func pressReleaseDeadline(for timeout: Duration) -> Duration {
        (timeout * 6).clamped(min: .milliseconds(1500), max: .seconds(3))
    }

    /// The immutable event data posted by a press-release guard. `CGEvent`
    /// posting is thread-safe and the event is not mutated after arming.
    nonisolated struct PressReleaseEvents: @unchecked Sendable {
        let mouseUp: CGEvent
        let pid: pid_t
    }

    /// Releases a synthetic press when an async move attempt stops making
    /// progress. A dangling press can turn the user's next real click into the
    /// end of a drag, including a drag that removes the status item.
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

        /// Test seam for driving the watchdog without sleeping or posting a
        /// real Core Graphics event.
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

        /// Cancels the independent safety post only after an acknowledged
        /// mouse-up. A failed normal or fallback release leaves it armed.
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

    /// Builds the independent safety release for one attempt.
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

    private static func isControlCenterOwned(_ item: MenuBarItem) -> Bool {
        item.owningApplication?.bundleIdentifier == MenuBarItemTag.Namespace.controlCenter.description
    }

    /// Supplies the live ownership inputs to the pure failure-attribution rule.
    func ledgerFailureKind(for error: any Error, item: MenuBarItem) -> MenuBarItemFailureLedger.FailureKind {
        guard let error = error as? EventError else {
            return .other
        }
        return Self.ledgerFailureKind(
            for: error,
            ownerIsControlCenter: Self.isControlCenterOwned(item),
            hasProvisionalIdentity: item.hasProvisionalIdentity
        )
    }

    private func recordLanding(of item: MenuBarItem) {
        failureLedger.recordSuccess(for: item)
        clearRefusedMove(of: item)
    }

    private func logStop(
        _ reason: MovePolicy.StopReason,
        attempt: Int,
        item: MenuBarItem,
        destination: MoveDestination,
        state: MovePolicy.State,
        maxAttempts: Int,
        error: (any Error)?
    ) {
        switch reason {
        case .refusedByMacOS:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(item.logString) returned to its starting origin after consecutive releases; abandoning the move"
            )
        case .targetMoved:
            let planned = state.plannedTargetMinX.map { String(format: "%.0f", $0) } ?? "?"
            let current = state.latestTargetMinX.map { String(format: "%.0f", $0) } ?? "?"
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) moved from minX=\(planned) to minX=\(current); abandoning the stale move"
            )
        case .targetRetreating:
            let history = state.targetMinXHistory.map { String(format: "%.0f", $0) }.joined(separator: " → ")
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) retreated on every recent attempt (\(history)); abandoning the move"
            )
        case .ownerUnresponsive:
            MenuBarItemManager.diagLog.warning("Attempt \(attempt): \(item.logString) owner is unresponsive")
        case .ownerAlwaysSilent:
            MenuBarItemManager.diagLog.warning("Attempt \(attempt): \(item.logString) repeated its standing silent-owner failure")
        case .ownerSilent, .other:
            MenuBarItemManager.diagLog.debug(
                "Attempt \(attempt) failed: \(error.map { "\($0)" } ?? "unknown error")"
            )
        case .itemGone:
            MenuBarItemManager.diagLog.warning("Attempt \(attempt): \(item.logString) no longer reports bounds")
        case .destinationGone:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) no longer reports bounds"
            )
        case .superseded:
            MenuBarItemManager.diagLog.debug("move: superseded during attempt \(attempt) for \(item.logString)")
        case .overran:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): the press on \(item.logString) outlived its deadline"
            )
        case .unsafePath:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(item.logString) has no safe transport to the selected destination"
            )
        case .budgetExhausted:
            MenuBarItemManager.diagLog.error(
                "move: all \(maxAttempts) attempt(s) exhausted without verifying \(item.logString) reached \(destination.logString)"
            )
        }
    }

    private func isAtDestination(
        _ item: MenuBarItem,
        for destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async -> Bool {
        await (try? itemHasCorrectPosition(item: item, for: destination, on: displayID)) ?? false
    }

    /// Rechecks plausible landings against a settled bar, then records and
    /// throws the policy's precise terminal verdict.
    private func concludeFailedMove(
        reason: MovePolicy.StopReason,
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        attempts: Int,
        budget: MoveTransactionBudget,
        lastError: (any Error)?
    ) async throws {
        if reason.deservesFinalLandingCheck, budget.elapsed < budget.limit {
            do {
                try await waitForLayoutToSettle(
                    item: item,
                    target: destination.targetItem,
                    budget: budget
                )
            } catch is MoveDeadlineExceeded {
                throw EventError.moveTimedOut(item)
            }
            if await isAtDestination(item, for: destination, on: displayID) {
                MenuBarItemManager.diagLog.info(
                    "Move landed: \(item.logString) after \(attempts) attempt(s); confirmed after stopping for \(reason.logString)"
                )
                recordLanding(of: item)
                return
            }
        }
        if reason == .budgetExhausted {
            await validateItemPositionAfterMove(item: item, destination: destination, on: displayID)
        }
        if reason == .refusedByMacOS {
            noteRefusedMove(of: item)
        }
        if reason.isFiledAgainstOwner, let lastError {
            failureLedger.recordFailure(for: item, kind: ledgerFailureKind(for: lastError, item: item))
        }
        MenuBarItemManager.diagLog.info(
            "Move verdict: \(reason.logString) for \(item.logString) after \(attempts) attempt(s) in \(Int(budget.elapsed.milliseconds)) ms"
        )
        throw Self.moveError(
            for: reason,
            item: item,
            destinationItem: destination.targetItem,
            lastError: lastError
        )
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
        let budget = Self.currentMoveBudget ?? MoveTransactionBudget(limit: Self.moveDeadline)

        // Admission waits for a bounded input lull before taking the app-wide
        // permit. Nested recovery moves already own the gate.
        if !Self.holdsMoveGate {
            do {
                try await Self.performWithMoveGate(
                    timeoutProvider: {
                        try budget.timeout(for: Self.moveGateTimeout)
                    },
                    waitBeforeGate: {
                        guard !skipInputPause else {
                            return
                        }
                        let allowance = try budget.timeout(for: Self.moveInputPauseLimit)
                        let waitTask = Task(timeout: allowance) {
                            try await self.waitForUserToPauseInput(
                                for: options.requiredInputPause,
                                timeout: options.inputPauseTimeout,
                                shouldContinue: options.shouldProceed
                            )
                        }
                        do {
                            switch try await waitTask.value {
                            case .paused:
                                break
                            case .timedOut:
                                throw EventError.inputPauseTimedOut(item)
                            case .superseded:
                                throw EventError.moveSuperseded(item)
                            }
                        } catch let error as EventError {
                            throw error
                        } catch {
                            _ = try budget.remaining()
                            MenuBarItemManager.diagLog.debug(
                                "move: input did not pause within \(allowance) for \(item.logString)"
                            )
                            throw EventError.cannotComplete
                        }
                    },
                    didFinishWhileHoldingGate: options.didFinishWhileHoldingGate,
                    operation: {
                        // Input can resume while queued. Recheck once without
                        // waiting while the gate is held.
                        if !skipInputPause {
                            let pauseMs = max(
                                0,
                                (Defaults.object(forKey: .inputPauseThresholdMs) as? Int)
                                    ?? Defaults.DefaultValue.inputPauseThresholdMs
                            )
                            guard self.hasUserPausedInput(for: .milliseconds(pauseMs)) else {
                                throw EventError.cannotComplete
                            }
                        }
                        var nestedOptions = options
                        nestedOptions.didFinishWhileHoldingGate = nil
                        _ = try budget.remaining()
                        try await Self.$currentMoveBudget.withValue(budget) {
                            try await self.move(
                                item: item,
                                to: destination,
                                on: displayID,
                                skipInputPause: true,
                                options: nestedOptions
                            )
                        }
                    }
                )
            } catch is MoveDeadlineExceeded {
                throw EventError.moveTimedOut(item)
            } catch is SimpleSemaphore.TimeoutError {
                if budget.elapsed >= budget.limit {
                    throw EventError.moveTimedOut(item)
                }
                MenuBarItemManager.diagLog.error("move: another move held the bar until admission timed out for \(item.logString)")
                throw EventError.moveEngineBusy(item)
            } catch {
                if budget.elapsed >= budget.limit {
                    throw EventError.moveTimedOut(item)
                }
                throw error
            }
            return
        }

        // Evaluate once, only after the transaction owns the gate. A caller
        // can reject a plan that became stale while queued without mistaking
        // the move's own subsequent updates for supersession.
        guard options.shouldBegin?() ?? true else {
            throw EventError.moveSuperseded(item)
        }

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
            try await budget.sleep(for: .milliseconds(250))
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

        // The plan may have waited behind another move (admission, gate
        // waiting). Resolve both endpoints again on the selected display and
        // require the same window, owner, stable tag, and resolved source.
        // A same-tag replacement needs a new plan; it is never a silent
        // transport fallback.
        _ = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: resolvedDisplayID
        )
        guard options.shouldProceed?() ?? true else {
            throw EventError.moveSuperseded(item)
        }
        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let initialBuffer = await moveOperationBufferDuration()
        if initialBuffer > .zero {
            try await budget.sleep(for: initialBuffer)
        }

        // The buffer itself is an await; require the same exact endpoints
        // again before the first verification or event.
        let bufferedEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: resolvedDisplayID
        )

        MenuBarItemManager.diagLog.info(
            """
            Moving \(item.logString) to \
            \(destination.logString) on display \(resolvedDisplayID)
            """
        )

        guard !Self.endpointsHaveCorrectPosition(bufferedEndpoints, for: destination) else {
            MenuBarItemManager.diagLog.debug("Item has correct position, cancelling move")
            recordLanding(of: item)
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
            let cursorWatchdog = min(
                options.watchdogTimeout ?? Self.cursorHideWatchdogTimeout(
                    maxAttempts: max(1, options.maxMoveAttempts)
                ),
                try budget.remaining()
            )
            MouseHelpers.hideCursor(watchdogTimeout: cursorWatchdog)
        }
        defer {
            if let mouseLocation {
                MouseHelpers.restoreCursorPosition(to: mouseLocation)
                MouseHelpers.showCursor()
            }
        }

        var policyState = MovePolicy.State(plannedTargetMinX: bufferedEndpoints.target.bounds.minX)
        let configuration = MovePolicy.Configuration(
            maxAttempts: max(1, options.maxMoveAttempts),
            displayWidth: CGDisplayBounds(resolvedDisplayID).width,
            itemIsControlItem: item.isControlItem,
            ownerHasSilentRecord: failureLedger.isUnresponsive(item)
        )
        var lastError: (any Error)?
        var stopReason: MovePolicy.StopReason?

        attemptLoop: while stopReason == nil {
            let n = policyState.attempts + 1
            guard !Task.isCancelled else {
                MenuBarItemManager.diagLog.debug("move: cancelled before attempt \(n) for \(item.logString)")
                throw EventError.cannotComplete
            }
            guard options.shouldProceed?() ?? true else {
                MenuBarItemManager.diagLog.debug("move: superseded before attempt \(n) for \(item.logString)")
                throw EventError.moveSuperseded(item)
            }
            guard MovePolicy.mayStartAnotherAttempt(elapsed: budget.elapsed, deadline: budget.limit) else {
                MenuBarItemManager.diagLog.warning(
                    "move: \(item.logString) has been moving for \(Int(budget.elapsed.milliseconds)) ms; not starting attempt \(n)"
                )
                stopReason = .overran
                break attemptLoop
            }

            let observation: MovePolicy.Observation
            var attemptStrategy: MoveStrategy?
            lastError = nil
            do {
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID),
                   MovePolicy.trustsPositionMatch(
                       attempt: n,
                       anyEventsSucceeded: policyState.anyEventsSucceeded,
                       itemIsControlItem: item.isControlItem
                   )
                {
                    MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
                    recordLanding(of: item)
                    return
                }

                let outcome = try await postMoveEvents(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID,
                    budget: budget,
                    warpCursorAfter: false
                )
                attemptStrategy = outcome.strategy
                try await waitForLayoutToSettle(
                    item: item,
                    target: destination.targetItem,
                    budget: budget
                )
                let settledEndpoints = try await resolveCurrentMoveEndpoints(
                    source: item,
                    destination: destination.targetItem,
                    on: resolvedDisplayID
                )
                let landed = Self.endpointsHaveCorrectPosition(settledEndpoints, for: destination)
                updateMoveOperationTimeout(
                    Self.nextMoveOperationTimeout(
                        after: outcome.timeout,
                        outcome: landed ? .landed : .displacedWithoutLanding
                    ),
                    for: item
                )
                observation = landed
                    ? .landed
                    : .displaced(
                        revertedToStart: outcome.revertedToStart,
                        targetMinX: settledEndpoints.target.bounds.minX
                    )
            } catch is MoveDeadlineExceeded {
                lastError = EventError.moveTimedOut(item)
                observation = .failed(.overran)
            } catch let error as EventError {
                lastError = error
                observation = .failed(MovePolicy.attemptFailure(for: error))
            } catch {
                lastError = error
                observation = .failed(.other)
            }

            switch MovePolicy.decide(
                after: observation,
                state: &policyState,
                configuration: configuration
            ) {
            case .succeed:
                MenuBarItemManager.diagLog.info(
                    "Move landed: \(item.logString) after \(n) attempt(s)\(attemptStrategy.map { " via \($0)" } ?? "")"
                )
                recordLanding(of: item)
                await validateItemPositionAfterMove(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID
                )
                return
            case .retry:
                if case .failed = observation {
                    MenuBarItemManager.diagLog.debug(
                        "Attempt \(n) failed: \(lastError.map { "\($0)" } ?? "unknown error")"
                    )
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "Attempt \(n) events succeeded but item not at destination, retrying"
                    )
                }
                let retryBuffer = await moveOperationBufferDuration()
                if retryBuffer > .zero {
                    try await budget.sleep(for: retryBuffer)
                }
            case let .stop(reason):
                stopReason = reason
                logStop(
                    reason,
                    attempt: n,
                    item: item,
                    destination: destination,
                    state: policyState,
                    maxAttempts: configuration.maxAttempts,
                    error: lastError
                )
            }
        }

        try await concludeFailedMove(
            reason: stopReason ?? .other,
            item: item,
            destination: destination,
            on: resolvedDisplayID,
            attempts: policyState.attempts,
            budget: budget,
            lastError: lastError
        )
    }
}
