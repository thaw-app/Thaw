//
//  PostRestrictionRepairSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// When the repair after a restriction reflow runs: once the reflow has had time to land, then again
/// while items stay parked or another reflow arrived mid-pass, a bounded number of times.
@MainActor
final class PostRestrictionRepairSchedule {
    /// Nudging MenuBarAgent mid-reflow parks collateral items at y≈1413; the wait also absorbs
    /// multi-hide bursts.
    static let firstDelay = Duration.milliseconds(1200)
    static let pollInterval = Duration.seconds(1)
    static let maximumPolls = 4

    /// The pending or running repair. Written only here and by the pass teardown, which cancels it.
    var task: Task<Void, Never>?
    /// A restriction change arrived while a pass was already running, so one more pass is owed.
    var needsRerun = false
    private(set) var isRunning = false

    private let sleep: @MainActor (Duration) async throws -> Void

    init(sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Starts the repair after the reflow delay, replacing one still waiting. A running pass only owes one more,
    /// since cancelling it would race its in-flight write with a drag; pass returns nil once superseded.
    func schedule(_ pass: @escaping @MainActor () async -> Bool?) {
        if isRunning {
            needsRerun = true
            return
        }
        task?.cancel()
        needsRerun = false
        task = Task { @MainActor [weak self] in
            await self?.run(pass)
        }
    }

    private func run(_ pass: @MainActor () async -> Bool?) async {
        do {
            try await sleep(Self.firstDelay)
        } catch {
            return
        }
        isRunning = true
        defer {
            isRunning = false
            needsRerun = false
        }
        guard var stillParked = await pass() else { return }
        var poll = 0
        while poll < Self.maximumPolls, stillParked || needsRerun {
            needsRerun = false
            do {
                try await sleep(Self.pollInterval)
            } catch {
                return
            }
            guard let parked = await pass() else { return }
            stillParked = parked
            poll += 1
        }
    }
}
