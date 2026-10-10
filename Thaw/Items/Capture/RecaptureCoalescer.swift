//
//  RecaptureCoalescer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// What one caller wants from a recapture pass.
nonisolated struct RecaptureDemand: Equatable, Sendable {
    var sections: [MenuBarSection.Name]

    /// Set by a deliberate post-reorder refresh, whose result must survive the
    /// recent-move guard.
    var ignoreRecentMove: Bool

    /// The pass occupying the slot when a request arrives.
    struct RunningPass: Equatable, Sendable {
        /// The sections it resolved as capturable when it started; nil before that.
        var capturing: Set<MenuBarSection.Name>?

        /// False once every caller awaiting it was cancelled, which cancels it.
        var hasWaiters: Bool
    }

    enum Placement: Equatable, Sendable {
        case start
        case mergeIntoRunning
        case joinRunning
        case followUp
    }

    /// Pure merge policy for timing-independent tests: sections accumulate and
    /// the recent-move bypass is sticky, so sharing never weakens a forced refresh.
    func merged(into pending: RecaptureDemand?) -> RecaptureDemand {
        guard let pending else { return self }
        let wanted = Set(pending.sections).union(sections)
        return RecaptureDemand(
            sections: MenuBarSection.Name.allCases.filter(wanted.contains),
            ignoreRecentMove: pending.ignoreRecentMove || ignoreRecentMove
        )
    }

    /// Where a request goes, given the sections it could capture right now.
    func placement(
        capturableNow: [MenuBarSection.Name],
        running: RunningPass?
    ) -> Placement {
        guard let running else { return .start }
        guard running.hasWaiters else { return .followUp }
        guard let capturing = running.capturing else { return .mergeIntoRunning }
        // A started pass may hold pixels older than this request, which a
        // forced refresh cannot accept.
        if !ignoreRecentMove, Set(capturableNow).isSubset(of: capturing) {
            return .joinRunning
        }
        return .followUp
    }
}

/// Runs one recapture pass at a time and folds overlapping requests into it
/// or into a single follow-up.
@MainActor
final class RecaptureCoalescer {
    typealias Capturable = @MainActor ([MenuBarSection.Name]) -> [MenuBarSection.Name]
    typealias PassBody = @MainActor (RecaptureDemand) async -> Bool

    private struct Pass {
        let id: UInt64
        var demand: RecaptureDemand
        var capturing: Set<MenuBarSection.Name>?
        var waiters = 1
        let task: Task<Bool, Never>
    }

    private var running: Pass?
    private var followUp: Pass?
    private var lastPassID: UInt64 = 0

    /// Serves demand with a pass that covers it and returns that pass's result.
    func run(
        _ demand: RecaptureDemand,
        capturable: @escaping Capturable,
        pass body: @escaping PassBody
    ) async -> Bool {
        // A cancelled caller captured nothing before either.
        guard !Task.isCancelled else { return false }
        let (id, task) = enlist(demand, capturable: capturable, body: body)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.abandon(id) }
        }
    }

    private func enlist(
        _ demand: RecaptureDemand,
        capturable: @escaping Capturable,
        body: @escaping PassBody
    ) -> (id: UInt64, task: Task<Bool, Never>) {
        let placement = demand.placement(
            capturableNow: capturable(demand.sections),
            running: running.map { .init(capturing: $0.capturing, hasWaiters: $0.waiters > 0) }
        )
        if var pass = running, placement == .mergeIntoRunning || placement == .joinRunning {
            if placement == .mergeIntoRunning {
                pass.demand = demand.merged(into: pass.demand)
            }
            pass.waiters += 1
            running = pass
            return (pass.id, pass.task)
        }
        if var pass = followUp {
            pass.demand = demand.merged(into: pass.demand)
            pass.waiters += 1
            followUp = pass
            return (pass.id, pass.task)
        }
        lastPassID += 1
        let id = lastPassID
        let previous = running?.task
        let task = Task {
            _ = await previous?.value
            return await self.execute(id, capturable: capturable, body: body)
        }
        let pass = Pass(id: id, demand: demand, task: task)
        if previous == nil {
            running = pass
        } else {
            followUp = pass
        }
        return (id, task)
    }

    private func execute(
        _ id: UInt64,
        capturable: Capturable,
        body: PassBody
    ) async -> Bool {
        // An abandoned follow-up was dropped from its slot and never promoted.
        guard running?.id == id, let demand = running?.demand else { return false }
        running?.capturing = Set(capturable(demand.sections))
        defer {
            // Hand the slot straight to the follow-up so no request starts a third pass.
            running = followUp
            followUp = nil
        }
        return await body(demand)
    }

    /// Drops one cancelled caller, cancelling a pass nobody is waiting for.
    private func abandon(_ id: UInt64) {
        if running?.id == id {
            running?.waiters -= 1
            if running?.waiters == 0 {
                running?.task.cancel()
            }
        } else if followUp?.id == id {
            followUp?.waiters -= 1
            if followUp?.waiters == 0 {
                followUp?.task.cancel()
                followUp = nil
            }
        }
    }
}
