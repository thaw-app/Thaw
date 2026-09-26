//
//  MenuBarItemManager+MoveGeometry.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics

// MARK: - Move Geometry

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

    /// Exact window only; a same-tag replacement is left for a fresh cache cycle.
    nonisolated func exactMoveBounds(
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
    func resolveCurrentMoveEndpoints(
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
    func validateMoveEndpointGeometry(
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

    func transportDecision(
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

    nonisolated func getTargetPoints(
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
    func itemHasCorrectPosition(
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

    private var faithfulDragMovesEnabled: Bool {
        (Defaults.object(forKey: .faithfulDragMoves) as? Bool) ?? Defaults.DefaultValue.faithfulDragMoves
    }
}
