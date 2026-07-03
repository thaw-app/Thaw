//
//  SyntheticMoveEngine.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Executes MenuBarAgent reorders through a synthetic Command-drag.
///
/// The engine owns gesture timing, AX-snapshot reuse, and verification. Its
/// caller owns cursor hiding and restoration so cursor state remains balanced
/// through the shared watchdog-backed ``MouseHelpers`` implementation. The
/// interface accepts the two environment operations that vary in tests/runtime:
/// event-source creation and live item enumeration.
@MainActor
struct SyntheticMoveEngine {
    typealias MoveDestination = MenuBarItemManager.MoveDestination
    typealias EventError = MenuBarItemManager.EventError

    private static let diagLog = DiagLog(category: "SyntheticMoveEngine")

    let eventSemaphore: SimpleSemaphore
    let makeEventSource: @MainActor () throws -> CGEventSource
    let enumerateItems: @MainActor () async -> [MenuBarItem]

    /// Posts the synthetic Command-drag gesture that physically reorders the
    /// item. Defaults to the real CGEvent-based implementation; tests inject
    /// a recording fake here so retry/dropX/anchoring behavior can be
    /// characterized without posting real hardware events.
    var postCommandDrag: @MainActor (CGPoint, CGPoint, CGEventSource) async -> Void =
        SyntheticMoveEngine.performCommandDrag

    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        maxAttempts: Int = 2,
        experimentalSystemItemHiding: Bool = false
    ) async throws {
        guard item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) else {
            Self.diagLog.warning("Refusing physical reorder source \(item.logString)")
            throw EventError.itemNotMovable(item)
        }

        guard destination.targetItem.isPhysicallyOrderable(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) || destination.targetItem.tag.matchesSectionBoundaryControlItem else {
            Self.diagLog.warning("Refusing anchored target \(destination.targetItem.logString)")
            throw EventError.itemNotMovable(destination.targetItem)
        }

        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            Self.diagLog.error("eventSemaphore timed out")
            throw EventError.cannotComplete
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        let source = try makeEventSource()
        let onScreenFrames = NSScreen.screens.map(\.frame)
        var liveItems = await enumerateItems()

        for attempt in 1 ... max(1, maxAttempts) {
            guard !Task.isCancelled else { throw EventError.cannotComplete }

            if LayoutPlanner.liveOrderSatisfiesDestination(
                items: liveItems,
                item: item,
                destination: destination,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) {
                return
            }

            let itemBounds = try currentBounds(for: item, in: liveItems)
            let targetBounds = try currentBounds(for: destination.targetItem, in: liveItems)
            let start = CGPoint(x: itemBounds.midX, y: itemBounds.midY)
            let inset = Constants.MenuBarTuning.syntheticDragDropInset
            let dropX: CGFloat = switch destination {
            case .leftOfItem: targetBounds.minX - inset
            case .rightOfItem: targetBounds.maxX + inset
            }
            let end = CGPoint(x: dropX, y: targetBounds.midY)

            guard onScreenFrames.contains(where: { $0.contains(start) }),
                  onScreenFrames.contains(where: { $0.contains(end) })
            else {
                throw EventError.itemNotMovable(item)
            }

            Self.diagLog.debug(
                "Attempt \(attempt): \(item.logString) \(destination.logString); " +
                    "order=\(LayoutPlanner.orderDescription(liveItems))"
            )
            await postCommandDrag(start, end, source)
            try await Task.sleep(for: Constants.MenuBarTuning.syntheticDragSettleDelay)

            // One AX walk supplies both verification and the next attempt's
            // source/target bounds. The old implementation performed separate
            // all-app walks for each endpoint and another for verification.
            liveItems = await enumerateItems()
            if LayoutPlanner.liveOrderSatisfiesDestination(
                items: liveItems,
                item: item,
                destination: destination,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) {
                return
            }
        }

        Self.diagLog.error(
            "Exhausted \(maxAttempts) attempts moving \(item.logString) \(destination.logString)"
        )
        throw EventError.cannotComplete
    }

    private func currentBounds(for item: MenuBarItem, in items: [MenuBarItem]) throws -> CGRect {
        if let match = items.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            items.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            items.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return match.bounds
        }
        throw EventError.missingItemBounds(item)
    }

    private static func performCommandDrag(
        from start: CGPoint,
        to end: CGPoint,
        source: CGEventSource
    ) async {
        func post(_ type: CGEventType, _ location: CGPoint) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else { return }
            event.flags = .maskCommand
            MoveInputSuppression.markSyntheticMoveEvent(event)
            event.post(tap: .cghidEventTap)
        }

        func pause(_ milliseconds: Int) async {
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }

        post(.mouseMoved, start)
        await pause(30)
        post(.leftMouseDown, start)
        await pause(60)

        let steps = 24
        for index in 1 ... steps {
            let progress = CGFloat(index) / CGFloat(steps)
            post(
                .leftMouseDragged,
                CGPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                )
            )
            await pause(16)
        }

        post(.leftMouseUp, end)
        await pause(40)
    }
}
