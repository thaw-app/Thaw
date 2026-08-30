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
        warpCursorAfter: Bool = true
    ) async throws -> MoveEventsOutcome {
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
        if warpIsOnScreen {
            await eventSleep(for: .milliseconds(20))
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
        let releaseGuard = makePressReleaseGuard(
            for: liveItem,
            mouseUp: mouseUp,
            eventPID: eventPID
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
                    on: displayID
                )
            } else {
                try await scrombleEvent(
                    mouseDown,
                    item: liveItem,
                    timeout: timeout
                )
                itemOrigin = try await waitForMoveEventResponse(
                    from: liveItem,
                    initialOrigin: itemOrigin,
                    timeout: timeout
                )

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
                try await scrombleEvent(
                    liveMouseUp,
                    item: releaseEndpoints.source,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
                releaseGuard.recordReleaseAttempt(delivered: true)
                itemOrigin = try await waitForMoveEventResponse(
                    from: releaseEndpoints.source,
                    initialOrigin: itemOrigin,
                    timeout: timeout
                )
            }
        } catch {
            let attemptError = error
            do {
                MenuBarItemManager.diagLog.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: liveItem,
                    timeout: .milliseconds(100), // Fixed timeout for fallback.
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
                releaseGuard.recordReleaseAttempt(delivered: true)
            } catch let fallbackError {
                // Keep the guard armed so its independent raw post remains
                // the final release path.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(fallbackError)")
            }
            timeout = Self.nextMoveOperationTimeout(after: timeout, outcome: .ownerDidNotRespond)
            updateMoveOperationTimeout(timeout, for: liveItem)
            if releaseGuard.didFire {
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
        on displayID: CGDirectDisplayID
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
            try await scrombleEvent(event, item: liveItem, timeout: timeout)
            responseItem = liveItem
            if step.subtype == .mouseDragged {
                await eventSleep(for: .milliseconds(8))
            }
        }
        itemOrigin = try await waitForMoveEventResponse(
            from: responseItem,
            initialOrigin: startOrigin,
            timeout: timeout
        )

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
        try await scrombleEvent(
            releaseEvent,
            item: releaseEndpoints.source,
            timeout: timeout,
            repeating: 2
        )
        releaseGuard.recordReleaseAttempt(delivered: true)

        // A revert returns to the start and therefore cannot be awaited as an
        // origin change after release. Give the drop one short settling beat
        // and re-resolve the exact source before reading its resting origin.
        await eventSleep(for: .milliseconds(30))
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
        eventPID: pid_t
    ) -> PressReleaseGuard {
        return PressReleaseGuard(
            deadline: Self.pressReleaseDeadline(for: getMoveOperationTimeout(for: item)),
            events: PressReleaseEvents(mouseUp: mouseUp, pid: eventPID),
            item: item
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
        // Admission waits for a bounded input lull before taking the app-wide
        // permit. Nested recovery moves already own the gate.
        if !Self.holdsMoveGate {
            do {
                try await Self.performWithMoveGate(
                    waitBeforeGate: {
                        guard !skipInputPause else {
                            return
                        }
                        let waitTask = Task(timeout: Self.moveInputPauseLimit) {
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
                            MenuBarItemManager.diagLog.debug(
                                "move: input did not pause within \(Self.moveInputPauseLimit) for \(item.logString)"
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
                        try await self.move(
                            item: item,
                            to: destination,
                            on: displayID,
                            skipInputPause: true,
                            options: nestedOptions
                        )
                    }
                )
            } catch is SimpleSemaphore.TimeoutError {
                MenuBarItemManager.diagLog.error(
                    "move: another move has held the bar for \(Self.moveGateTimeout); giving up on \(item.logString)"
                )
                throw EventError.moveEngineBusy(item)
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
        let plannedTargetBounds = try? exactMoveBounds(for: destination.targetItem, isDestination: true)

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
                let outcome = try await postMoveEvents(
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
                        after: outcome.timeout,
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
                let currentTargetBounds = try? exactMoveBounds(
                    for: destination.targetItem,
                    isDestination: true
                )
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
                if case EventError.missingDestinationBounds = error {
                    MenuBarItemManager.diagLog.warning(
                        "Attempt \(n): \(destination.targetItem.logString) no longer reports bounds, abandoning the destination"
                    )
                    throw error
                }
                if case EventError.moveTimedOut = error {
                    throw error
                }
                if case EventError.unsafeMovePath = error {
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
