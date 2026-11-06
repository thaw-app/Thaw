//
//  BarSettling.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Whether the menu bar is still settling after Thaw's launch, an app launch, a display change or a
/// spacing wave. Callers report what happened; the item cache's owner attaches a Host for the samples.
@MainActor
final class BarSettling {
    private static let diagLog = DiagLog(category: "BarSettling")
    static nonisolated let stableTarget = 3

    private let now: @MainActor () -> ContinuousClock.Instant
    private let sleep: @MainActor (Duration) async throws -> Void
    private let pollInterval: Duration
    private let minimumDuration: Duration
    private var host = Host.idle

    private(set) var isSettling = false
    private(set) var kind: Kind?
    /// Bundle IDs the running settle waits on, including those of launches that yielded to it.
    private(set) var expectedBundleIDs = Set<String>()
    private var deadline: ContinuousClock.Instant?
    private var task: Task<Void, Never>?

    init(
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0, tolerance: .milliseconds(100)) },
        pollInterval: Duration = Constants.MenuBarTuning.startupSettlingPollInterval,
        minimumDuration: Duration = Constants.MenuBarTuning.startupMenuBarHostSettleDelay
    ) {
        self.now = now
        self.sleep = sleep
        self.pollInterval = pollInterval
        self.minimumDuration = minimumDuration
    }

    /// Set once by the owner of the item cache.
    func attach(_ host: Host) {
        self.host = host
    }

    /// A weaker disturbance joins a stronger settle and adds its bundle IDs; otherwise it replaces the
    /// settle, keeping the later deadline.
    func note(_ disturbance: Disturbance) {
        if case .spacingWaveEnded = disturbance {
            callOff(disturbance)
            return
        }
        let label = disturbance.label
        let merged = expectedBundleIDs.union(disturbance.expectedBundleIDs)
        let incoming = disturbance.kind
        if let existing = kind, Self.yields(incoming: incoming, to: existing) {
            expectedBundleIDs = merged
            Self.diagLog.debug("\(label): settling start ignored; \(existing) settling already in flight")
            return
        }

        let maxDuration = disturbance.maxDuration
        let newDeadline = now().advanced(by: maxDuration)
        let deadline = max(self.deadline ?? newDeadline, newDeadline)
        self.deadline = deadline
        expectedBundleIDs = merged
        let adopts = Self.adoptsObservedMembership(incoming: incoming, replacing: kind)
        kind = incoming
        // The cancelled task exits without touching shared state.
        task?.cancel()
        isSettling = true
        host.didStart()
        Self.diagLog.debug("\(label): settling period started (max duration: \(maxDuration))")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await run(disturbance, until: deadline, adopts: adopts, waitsForSet: !merged.isEmpty)
        }
    }

    /// Follows any settle that replaces the awaited one, through the work its host owes afterwards.
    /// Returns early if the caller is cancelled.
    func settled() async {
        await SettlingWait.follow(isSettling: { isSettling }, currentTask: { task })
    }

    // MARK: Rules

    static nonisolated func yields(incoming: Kind, to existing: Kind) -> Bool {
        switch incoming {
        case .preflight: existing != .preflight
        case .event: existing == .cold || existing == .expectedSet
        case .cold, .expectedSet: false
        }
    }

    /// A concealed item's weight can still sit in the Visible band in Manual, so a read after a later
    /// settle would undo Layout edits. An app relaunch that takes over the launch settle still owes it.
    static nonisolated func adoptsObservedMembership(incoming: Kind, replacing existing: Kind?) -> Bool {
        incoming == .cold || existing == .cold
    }

    /// After a display change macOS keeps re-laying the bar past a stable count, and a restore read
    /// from those frames scrambles it, so that settle also waits for the mirror's quiet clock.
    static nonisolated func verdict(
        for sample: Sample,
        expecting: Set<String>?,
        minimumElapsed: Bool,
        waitsForQuietBar: Bool,
        streak: inout Streak
    ) -> Verdict {
        let pidsOK = sample.managedCount > 0 && sample.unresolvedPIDs <= 1
        if let expecting {
            let missing = expecting.subtracting(sample.bundleIDs)
            if missing.isEmpty, pidsOK, minimumElapsed, sample.hostReady {
                return .settled
            }
            return .waiting(.missing(missing))
        }

        let barQuiet = !waitsForQuietBar || sample.barQuiet
        if pidsOK, sample.managedCount == streak.lastSeenCount, minimumElapsed, sample.hostReady, barQuiet {
            streak.stablePolls += 1
            return streak.stablePolls >= stableTarget ? .settled : .waiting(.counting)
        }
        let wait: Wait = if sample.managedCount != streak.lastSeenCount {
            .countChanged(from: streak.lastSeenCount, to: sample.managedCount)
        } else if !minimumElapsed {
            .minimumNotElapsed
        } else if !sample.hostReady {
            .hostNotReady
        } else if !barQuiet {
            .barNotQuiet
        } else {
            .pidsUnresolved
        }
        streak.stablePolls = 0
        streak.lastSeenCount = sample.managedCount
        return .waiting(wait)
    }

    // MARK: Running a settle

    private func run(_ disturbance: Disturbance, until deadline: ContinuousClock.Instant, adopts: Bool, waitsForSet: Bool) async {
        let label = disturbance.label
        await host.awaitInitialRead()

        var streak = Streak()
        var hitDeadline = false
        let startedAt = now()
        if waitsForSet {
            Self.diagLog.debug("\(label): waiting for \(expectedBundleIDs.count) expected bundle ID(s) to reattach")
        }

        while !Task.isCancelled {
            if now() > deadline {
                Self.diagLog.debug("\(label): settling hit max deadline (\(deadline)), ending with fallback")
                hitDeadline = true
                break
            }
            let sample = await host.sample()
            // Read on every poll: an app launch that yielded to this wait adds its ID later.
            let verdict = Self.verdict(
                for: sample,
                expecting: waitsForSet ? expectedBundleIDs : nil,
                minimumElapsed: startedAt.duration(to: now()) >= minimumDuration,
                waitsForQuietBar: disturbance.waitsForQuietBar,
                streak: &streak
            )
            if verdict == .settled {
                logSettled(label, sample: sample, waitsForSet: waitsForSet)
                break
            }
            if case let .waiting(wait) = verdict {
                logWaiting(label, wait)
            }
            do {
                try await sleep(pollInterval)
            } catch is CancellationError {
                Self.diagLog.debug("\(label): settling task cancelled")
                return
            } catch {
                return
            }
        }

        guard !Task.isCancelled else { return }
        isSettling = false
        self.deadline = nil
        expectedBundleIDs.removeAll()
        kind = nil
        Self.diagLog.debug("\(label): settling period ended")
        await host.didSettle(Ending(disturbance: disturbance, adoptsObservedMembership: adopts, hitDeadline: hitDeadline))
    }

    /// Refused while relaunched apps are still awaited, during the launch settle, and during a display
    /// or launch settle the preflight joined: a partial cache would report every item in place.
    private func callOff(_ disturbance: Disturbance) {
        let label = disturbance.label
        guard isSettling || task != nil else { return }
        if !expectedBundleIDs.isEmpty {
            Self.diagLog.debug("\(label): settling cancel ignored; \(expectedBundleIDs.count) expected bundle ID(s) still pending")
            return
        }
        switch kind {
        case .cold:
            Self.diagLog.debug("\(label): settling cancel ignored; performSetup settling in flight")
            return
        case .event:
            Self.diagLog.debug("\(label): settling cancel ignored; display or launch settling in flight")
            return
        case .preflight, .expectedSet, nil:
            break
        }
        task?.cancel()
        task = nil
        isSettling = false
        deadline = nil
        kind = nil
        Self.diagLog.debug("\(label): settling period cancelled")
    }

    private func logSettled(_ label: String, sample: Sample, waitsForSet: Bool) {
        if waitsForSet {
            Self.diagLog.debug("\(label): all expected bundle ID(s) reattached, ending early")
        } else {
            Self.diagLog.debug(
                "\(label): settled (count=\(sample.managedCount) stable for \(Self.stableTarget) polls, \(sample.unresolvedPIDs) nil PIDs), ending early"
            )
        }
    }

    private func logWaiting(_ label: String, _ wait: Wait) {
        switch wait {
        case let .missing(missing):
            Self.diagLog.debug("\(label): \(missing.count) bundle ID(s) still missing: \(missing.sorted().joined(separator: ", "))")
        case let .countChanged(from, to):
            Self.diagLog.debug("\(label): count changed \(from) -> \(to), resetting stability")
        case .minimumNotElapsed:
            Self.diagLog.debug("\(label): count stable but minimum settle \(minimumDuration) not elapsed yet")
        case .hostNotReady:
            Self.diagLog.debug("\(label): waiting for menu bar host modules (MenuBarAgent / BentoBox)")
        case .barNotQuiet:
            Self.diagLog.debug("\(label): waiting for the bar to go quiet after the display change")
        case .counting, .pidsUnresolved:
            break
        }
    }
}
