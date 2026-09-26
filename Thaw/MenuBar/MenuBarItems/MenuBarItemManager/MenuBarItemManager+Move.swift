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
    nonisolated enum MoveDestination: Equatable {
        case leftOfItem(MenuBarItem)
        case rightOfItem(MenuBarItem)

        var targetItem: MenuBarItem {
            switch self {
            case let .leftOfItem(item), let .rightOfItem(item): item
            }
        }

        /// Same side, against the freshly enumerated destination window.
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
        /// Parked targets use their vertical midpoint so an event clamped to the
        /// edge can't trigger a top Hot Corner.
        func targetPoint(in targetBounds: CGRect, on displayBounds: CGRect) -> CGPoint {
            let targetIsParkedOffscreen = targetBounds.maxX <= displayBounds.minX
            let targetY = targetIsParkedOffscreen ? targetBounds.midY : targetBounds.minY
            // A drop on a control item's own edge lets AppKit pick either side,
            // and it picks wrong (#923). Bias one point into the requested side.
            // Applies to wide parked dividers and to the chevron too (#1035).
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
        /// A parked target strands the item beside it off-screen. Uses the leading
        /// edge, like the drop point.
        ///
        /// Not on its own a reason to refuse: concealing drops land off-screen by
        /// design. Only visible-bound items are stranded.
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

    /// Parked and cross-notch teleports are named separately so an unsafe plan
    /// can't silently fall back to press-at-destination.
    nonisolated enum MoveStrategy: Equatable, CustomStringConvertible {
        case teleport
        case faithfulDrag
        case parkedTeleport
        case crossNotchTeleport
        /// Presses on the source, releases at the destination. Some freshly
        /// re-registered items reject the usual teleport.
        case sourceAnchoredTeleport

        var description: String {
            switch self {
            case .teleport: "teleport"
            case .faithfulDrag: "faithfulDrag"
            case .parkedTeleport: "parkedTeleport"
            case .crossNotchTeleport: "crossNotchTeleport"
            case .sourceAnchoredTeleport: "sourceAnchoredTeleport"
            }
        }

        /// Whether to release at the pre-press point: while a parked item is held,
        /// its lane reads as reflowed by ~1000 points (#1074).
        func keepsPlannedReleasePoint(
            targetDisposition: MoveEndpointDisposition
        ) -> Bool {
            switch self {
            case .parkedTeleport:
                return true
            case .sourceAnchoredTeleport:
                // A source-anchored retry can address a visible destination,
                // where the reflow is real and the fresh point is correct.
                return targetDisposition == .parked
            case .teleport, .faithfulDrag, .crossNotchTeleport:
                return false
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

    /// Screen coordinates can't identify parked items, since a real display may
    /// sit left of the selected one.
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
        if isOnScreen,
           let physicalDisplay = displays.first(where: { $0.bounds.contains(center) })
        {
            return physicalDisplay.id == selectedDisplayID
                ? .selectedDisplay
                : .otherDisplay(physicalDisplay.id)
        }

        // kCGWindowIsOnscreen is about Spaces, not displays; Tahoe reports it
        // true for parked items. The parked lane wins over a left display.
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

    /// One absolute budget for the whole transaction; nested waits get only what's left.
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

    /// A nil endpoint display means parked off-screen; another display means a
    /// stale or cross-display plan, which is rejected.
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

    /// Never falls back to a same-tag window: a relaunch or clone isn't the endpoint.
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

        // Equal X means mid-reflow; any tie-break could certify the wrong side.
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

    /// Lets the full-bar list skip source-PID resolution while the two endpoints
    /// stay freshly resolved.
    static nonisolated func replacingMoveEndpoints(
        in snapshot: [MenuBarItem],
        with endpoints: [MenuBarItem]
    ) -> [MenuBarItem] {
        let endpointsByWindowID = Dictionary(
            endpoints.map { ($0.windowID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return snapshot.map { endpointsByWindowID[$0.windowID] ?? $0 }
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

    /// Whole transactions, not just posts, or two retry loops undo each other.
    private static let moveGate = SimpleSemaphore(value: 1)

    /// Lets a blocked-item recovery move nested inside its parent pass the gate.
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

    /// Polls until two readings agree. The confirmation bit is separate so a
    /// still-changing last sample isn't mistaken for settled.
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

    /// Control Center animates the reflow after release, so an immediate read
    /// can reject a correct drop.
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

    /// A budget, not a cost: the response poll returns as soon as the item moves.
    /// 100 ms was too little under contention, worst at startup (#687).
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Control Center groups respond a little slower.
            return .milliseconds(350)
        }
        return .milliseconds(250)
    }

    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Growth is adopted as is; only shrinkage is smoothed. Smoothing growth
    /// too crept up too slowly to help (#687).
    ///
    /// Floor 75 ms, below which retry cascades start. Ceiling 1 s, past which
    /// the item is unresponsive rather than slow.
    static nonisolated func mergedMoveOperationTimeout(
        proposed: Duration,
        current: Duration
    ) -> Duration {
        let next = proposed > current ? proposed : (proposed + current) / 2
        return next.clamped(min: .milliseconds(75), max: .seconds(1))
    }

    /// Covers a single move's worst case: every attempt at the ceiling, four
    /// waits each, plus a 100 ms fallback. Never below 10 s, so a slow item
    /// can't outlast it and show the cursor mid-sequence.
    static nonisolated func cursorHideWatchdogTimeout(
        operationCeiling: Duration = .seconds(1),
        maxAttempts: Int = 8,
        fallbackPost: Duration = .milliseconds(100),
        floor: Duration = .seconds(10)
    ) -> Duration {
        // One millisecond is 10^15 attoseconds.
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

    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        moveOperationTimeouts[item.tag] = Self.mergedMoveOperationTimeout(
            proposed: timeout,
            current: getMoveOperationTimeout(for: item)
        )
    }

    func pruneMoveOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        moveOperationTimeouts = moveOperationTimeouts.filter { validTags.contains($0.key) }
    }

    private func getDefaultClickOperationTimeout(for item: MenuBarItem) -> Duration {
        // Slow apps with dynamic content.
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

    func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = clickOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultClickOperationTimeout(for: item)
    }

    func updateClickOperationTimeout(_ duration: Duration, for item: MenuBarItem) {
        let current = getClickOperationTimeout(for: item)
        let average = (duration + current) / 2
        let clamped = average.clamped(min: .milliseconds(200), max: .milliseconds(1000))
        clickOperationTimeouts[item.tag] = clamped
        MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(duration.milliseconds))ms)")
    }

    func pruneClickOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickOperationTimeouts = clickOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// Exact window only; a same-tag replacement is left for a fresh cache cycle.
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

    /// Refreshes both endpoints. Ordinal checks also enumerate the bar without
    /// source PIDs, then overlay the two resolved endpoints.
    private func resolveCurrentMoveEndpoints(
        source expectedSource: MenuBarItem,
        destination expectedDestination: MenuBarItem,
        on displayID: CGDirectDisplayID,
        requiresFullSnapshot: Bool = false
    ) async throws -> CurrentMoveEndpoints {
        let endpoints = await MenuBarItem.refreshMoveEndpoints([
            expectedSource,
            expectedDestination,
        ])
        let items: [MenuBarItem]
        if requiresFullSnapshot {
            let geometrySnapshot = await MenuBarItem.getMenuBarItems(
                on: displayID,
                option: .activeSpace,
                resolveSourcePID: false
            ).filter { !$0.isSystemClone }
            items = Self.replacingMoveEndpoints(
                in: geometrySnapshot,
                with: endpoints
            )
        } else {
            let endpointWindowIDs = Set(endpoints.map(\.windowID))
            let freshDividers = authoritativeMoveGeometryDividers().filter {
                !endpointWindowIDs.contains($0.windowID)
            }
            items = endpoints + freshDividers
        }

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

    /// Fresh divider records from windows Thaw owns directly. These provide
    /// parked-lane geometry without another full menu-bar enumeration.
    private func authoritativeMoveGeometryDividers() -> [MenuBarItem] {
        guard let appState else { return [] }
        return [MenuBarSection.Name.hidden, .alwaysHidden].compactMap { identifier in
            guard let window = appState.menuBarManager.controlItem(withName: identifier)?.window,
                  let windowID = Self.windowServerID(windowNumber: window.windowNumber)
            else {
                return nil
            }
            return MenuBarItem.ownControlItem(windowID: windowID)
        }
    }

    /// Tells a parked item apart from a window on a display to the left.
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

    /// Whether item is now the immediate neighbor of the destination's target
    /// on the requested side.
    ///
    /// Ordinal, not coordinates: our own drag displaces the target, so comparing
    /// coordinates fails on a reflowing bar (#900). One snapshot, exact window IDs.
    ///
    /// - Note: source PIDs are left unresolved; only tags, IDs and bounds are needed.
    ///
    /// Main-actor isolated rather than nonisolated: the enumeration and the
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
            on: displayID,
            requiresFullSnapshot: true
        )
        return Self.endpointsHaveCorrectPosition(endpoints, for: destination)
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
    private func postMoveEvents(
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

    /// Always releases on the bar before propagating a failure.
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

    private var faithfulDragMovesEnabled: Bool {
        (Defaults.object(forKey: .faithfulDragMoves) as? Bool) ?? Defaults.DefaultValue.faithfulDragMoves
    }

    /// Blocked items sit at x=-1 and can't be interacted with normally.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try exactMoveBounds(for: item)
            return bounds.origin.x == -1
        } catch {
            return false
        }
    }

    /// Rescues an item that got stuck at x=-1 after a move into hidden.
    private func validateItemPositionAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async {
        // Only moves targeting the hidden divider; others were placed on purpose.
        switch destination {
        case let .leftOfItem(anchor), let .rightOfItem(anchor):
            guard anchor.tag == .alwaysHiddenControlItem else { return }
        }

        if await isItemBlocked(item) {
            MenuBarItemManager.diagLog.warning("Item \(item.logString) stuck at x=-1 after move - attempting recovery")

            guard let appState else { return }
            guard let hiddenControlItem = appState.menuBarManager.controlItem(withName: .hidden)?.window else {
                MenuBarItemManager.diagLog.error("Cannot recover item: missing hidden control item window")
                return
            }

            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard
                let hiddenWindowID = Self.windowServerID(
                    windowNumber: hiddenControlItem.windowNumber
                ),
                let hiddenMenuBarItem = items.first(where: { $0.windowID == hiddenWindowID })
            else {
                MenuBarItemManager.diagLog.error("Cannot recover item: control item not found in menu bar items")
                return
            }

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

    /// Exposes isItemBlocked for drag-failure callers.
    func isItemCurrentlyBlocked(_ item: MenuBarItem) async -> Bool {
        await isItemBlocked(item)
    }

    /// Moves a blocked item just right of the hidden divider. Doesn't retry the
    /// original move; that's up to the caller.
    ///
    /// - Returns: true if the rescue move completed without throwing.
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
        /// The item landed; verification raced macOS's settle.
        case suppress
        /// Stuck at x=-1: rescue to visible and retry once.
        case rescueAndRetry
        /// The hidden divider couldn't be resolved and recovery is already running.
        /// Show a specific message instead of the raw error.
        case alertControlItemsMissing
        /// Show the raw error.
        case alertGeneric
    }

    /// Precedence: landed beats blocked, blocked beats missing control items.
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

    /// Every field defaults, so callers pass only what they change.
    struct MoveOptions {
        var requiredInputPause: Duration?
        var inputPauseTimeout: Duration?
        var watchdogTimeout: Duration?
        var maxMoveAttempts: Int = 8
        var hideCursorAcrossAttempts: Bool = true
        var shouldProceed: (@MainActor () -> Bool)?
        /// Checked once the gate is held; false supersedes a move that went
        /// stale while queued.
        var shouldBegin: (@MainActor () -> Bool)?
        /// Runs while the gate is still held, after the move finished but
        /// before another move may enter.
        var didFinishWhileHoldingGate: (@MainActor () -> Void)?
        /// The user asked for this move, directly or by revealing an item.
        /// It bypasses the move circuit breaker and, on landing, clears it.
        var isUserInitiated = false
    }

    /// Shorter than the cursor watchdog and queued callers' patience.
    static nonisolated let moveDeadline: Duration = .seconds(8)

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
        case .staleDestination:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) no longer matches the move plan"
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
    /// - Parameter options: The move tunables; every field defaults.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        options: MoveOptions = .init()
    ) async throws {
        let budget = Self.currentMoveBudget ?? MoveTransactionBudget(limit: Self.moveDeadline)

        // Nested recovery moves already own the gate.
        if !Self.holdsMoveGate {
            // Runaway guard. Superseded, not failed: the item did nothing
            // wrong, so no caller files the refusal against it.
            if moveCircuitBreaker.isOpen {
                if !options.isUserInitiated {
                    MenuBarItemManager.diagLog.debug(
                        "Move circuit breaker open; skipping automatic move of \(item.logString)"
                    )
                    throw EventError.moveSuperseded(item)
                }
                MenuBarItemManager.diagLog.info(
                    "Move circuit breaker open; allowing the user's move of \(item.logString)"
                )
            }
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
                        } catch is TaskTimeoutError {
                            // The budget ran out before the pause wait's own
                            // timeout; still an input-pause deferral.
                            MenuBarItemManager.diagLog.debug(
                                "move: input did not pause within \(allowance) for \(item.logString)"
                            )
                            throw EventError.inputPauseTimedOut(item)
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
                        // Input can resume while queued; recheck without waiting.
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
            if options.isUserInitiated {
                moveCircuitBreaker.noteUserOverride()
            }
            return
        }

        // Once, after taking the gate, so the move's own updates don't read as supersession.
        guard options.shouldBegin?() ?? true else {
            throw EventError.moveSuperseded(item)
        }

        // Backstop: a dragged clone displaces real items. It vanishes on its own,
        // so a no-op is correct.
        guard !item.isSystemClone else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - system status item clone")
            return
        }
        guard item.isMovableAddressingWindowOwner else {
            // Tells a macOS prohibition apart from an identity-resolution failure (#905).
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

        // A synthetic Cmd-drag tears down an open menu. Wait briefly, then give up.
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

        // Right-of moves are the rescue path; anything else could drag a stuck
        // item somewhere unknown.
        if await isItemBlocked(item) {
            guard case .rightOfItem = destination else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        let resolvedDisplayID: CGDirectDisplayID = if let displayID {
            displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            window.displayID
        } else {
            Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        // The plan may have waited in the queue. Require the same window, owner,
        // tag, and source; a same-tag replacement needs a new plan.
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

        // The buffer is an await, so check the endpoints again.
        let bufferedEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: resolvedDisplayID,
            requiresFullSnapshot: true
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

        if !options.isUserInitiated {
            moveCircuitBreaker.note(.move(identifier: item.uniqueIdentifier))
        }

        // Warp back once after all attempts, not per attempt, or the cursor oscillates.
        let mouseLocation = options.hideCursorAcrossAttempts ? try getMouseLocation() : nil
        let cursorOwnershipStartedAt = ContinuousClock.now
        // The default 1 s watchdog is far too short; a premature fire flashes the
        // cursor mid-display. See cursorHideWatchdogTimeout.
        if options.hideCursorAcrossAttempts {
            let cursorWatchdog = try min(
                options.watchdogTimeout ?? Self.cursorHideWatchdogTimeout(
                    maxAttempts: max(1, options.maxMoveAttempts)
                ),
                budget.remaining()
            )
            MouseHelpers.hideCursor(watchdogTimeout: cursorWatchdog)
        }
        defer {
            if let mouseLocation {
                let physicalInputOccurred = MouseHelpers.physicalPointerInputOccurred(
                    since: cursorOwnershipStartedAt
                )
                if MouseHelpers.shouldRestoreSavedCursorPosition(
                    physicalPointerInputOccurred: physicalInputOccurred
                ) {
                    MouseHelpers.restoreCursorPosition(to: mouseLocation)
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "move: preserving physical pointer movement made during the transaction"
                    )
                }
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
                    warpCursorAfter: false,
                    preferSourceAnchoredTeleport: policyState.revertedRun > 0
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
                    on: resolvedDisplayID,
                    requiresFullSnapshot: true
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

        if !options.isUserInitiated {
            moveCircuitBreaker.note(.failedMove)
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
