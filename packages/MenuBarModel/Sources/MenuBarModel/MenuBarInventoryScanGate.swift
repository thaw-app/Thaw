//
//  MenuBarInventoryScanGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Shares discovery work without allowing a move to consume a pre-request scan.
/// The walk must stop cooperatively and return its retained state on cancellation.
public actor MenuBarInventoryScanGate<Observation: Sendable, Snapshot: Sendable> {
    public typealias Walk = @Sendable (
        MenuBarScanState<Observation>, MenuBarScanScope, Set<Int32>
    ) async -> (snapshot: Snapshot, state: MenuBarScanState<Observation>)

    private struct InFlight {
        let id: UInt64
        let scope: MenuBarScanScope
        let priorityOwners: Set<Int32>
        let task: Task<Snapshot, Never>
    }

    private let walk: Walk
    private var state = MenuBarScanState<Observation>()
    private var latestID: UInt64 = 0
    private var inFlight: InFlight?

    public init(walk: @escaping Walk) {
        self.walk = walk
    }

    public func snapshot(
        freshOnly: Bool,
        scope: MenuBarScanScope = .discovery,
        priorityOwners: Set<Int32> = [],
        preemptsDiscovery: Bool = true
    ) async -> Snapshot? {
        let requestedAfter = latestID
        while let existing = inFlight {
            guard !Task.isCancelled else { return nil }
            let coversRequest = existing.scope == scope &&
                (scope == .discovery || priorityOwners.isSubset(of: existing.priorityOwners))
            if coversRequest, !freshOnly || existing.id > requestedAfter {
                let snapshot = await existing.task.value
                return Task.isCancelled ? nil : snapshot
            }
            // A periodic reader waits instead, or its cadence would starve discovery.
            if preemptsDiscovery, scope != .discovery, existing.scope == .discovery {
                existing.task.cancel()
            }
            _ = await existing.task.value
        }
        guard !Task.isCancelled else { return nil }
        latestID += 1
        let id = latestID
        let previous = state
        let walk = self.walk
        let task = Task.detached(priority: Task.currentPriority) {
            let result = await walk(previous, scope, priorityOwners)
            await self.finish(id: id, state: result.state)
            return result.snapshot
        }
        inFlight = InFlight(id: id, scope: scope, priorityOwners: priorityOwners, task: task)
        let snapshot = await task.value
        return Task.isCancelled ? nil : snapshot
    }

    private func finish(id: UInt64, state: MenuBarScanState<Observation>) {
        guard inFlight?.id == id else { return }
        self.state = state
        inFlight = nil
    }
}
