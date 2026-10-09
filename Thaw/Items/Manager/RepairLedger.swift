//
//  RepairLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The account of what each piece of repair work was asked for.
///
/// A request is stamped with its cause. Requests for the same work merge until
/// it runs, so a run can say what set it off and how many requests it stood
/// for. Pure bookkeeping: it admits nothing and delays nothing. Admission is
/// ``RepairLane``'s job, and ``RepairOrchestrator`` puts the two together.
struct RepairLedger {
    typealias Work = RepairOrchestrator.Work
    typealias Cause = RepairOrchestrator.Cause

    /// How often one cause asked before the work ran.
    struct CauseCount: Equatable, Sendable {
        let cause: Cause
        let count: Int
    }

    /// What a piece of work had absorbed by the time it ran.
    struct Run: Equatable, Sendable {
        let work: Work
        /// In the order each cause first asked.
        let causes: [CauseCount]
        /// Every request merged into this run.
        let requests: Int
        /// From the first merged request to the run. Zero when nothing asked.
        let waited: Duration
        /// Work still running when this started, in declaration order.
        let overlapping: [Work]

        /// "restrictionChanged×3, settled" for the log.
        var causeSummary: String {
            guard !causes.isEmpty else { return "unrequested" }
            return causes
                .map { $0.count > 1 ? "\($0.cause.rawValue)×\($0.count)" : $0.cause.rawValue }
                .joined(separator: ", ")
        }
    }

    private struct Pending {
        let firstRequestedAt: ContinuousClock.Instant
        var order: [Cause] = []
        var counts: [Cause: Int] = [:]

        mutating func add(_ cause: Cause) {
            if counts[cause] == nil {
                order.append(cause)
            }
            counts[cause, default: 0] += 1
        }

        var causes: [CauseCount] {
            order.map { CauseCount(cause: $0, count: counts[$0] ?? 0) }
        }

        var requests: Int {
            counts.values.reduce(0, +)
        }
    }

    private var pending: [Work: Pending] = [:]
    private var running: [Work: ContinuousClock.Instant] = [:]
    private var runCounts: [Work: Int] = [:]
    private var overlapCount = 0

    /// Stamps a request. Requests for the same work merge until it runs.
    mutating func request(_ work: Work, cause: Cause, at now: ContinuousClock.Instant = .now) {
        pending[work, default: Pending(firstRequestedAt: now)].add(cause)
    }

    /// Forgets what was asked of work whose scheduler declined to arm it, so
    /// the requests are not credited to a later, unrelated run.
    mutating func withdraw(_ work: Work) {
        pending[work] = nil
    }

    /// Marks work as running and hands back what it absorbed.
    mutating func begin(_ work: Work, at now: ContinuousClock.Instant = .now) -> Run {
        let absorbed = pending.removeValue(forKey: work)
        let overlapping = Work.allCases.filter { $0 != work && running[$0] != nil }
        running[work] = now
        runCounts[work, default: 0] += 1
        if !overlapping.isEmpty {
            overlapCount += 1
        }
        return Run(
            work: work,
            causes: absorbed?.causes ?? [],
            requests: absorbed?.requests ?? 0,
            waited: absorbed.map { $0.firstRequestedAt.duration(to: now) } ?? .zero,
            overlapping: overlapping
        )
    }

    /// Marks work as finished and returns how long it ran.
    @discardableResult
    mutating func end(_ work: Work, at now: ContinuousClock.Instant = .now) -> Duration {
        guard let began = running.removeValue(forKey: work) else { return .zero }
        return began.duration(to: now)
    }

    /// The causes waiting on work that has not run yet, in the order they asked.
    func causesWaiting(for work: Work) -> [Cause] {
        pending[work]?.order ?? []
    }

    func isRunning(_ work: Work) -> Bool {
        running[work] != nil
    }

    /// Diagnostics for the log.
    var stateDescription: String {
        func names(_ works: [Work]) -> String {
            works.map(\.rawValue).joined(separator: ",")
        }
        let runs = Work.allCases
            .compactMap { work in runCounts[work].map { "\(work.rawValue)=\($0)" } }
            .joined(separator: " ")
        let awake = names(Work.allCases.filter { running[$0] != nil })
        let waiting = names(Work.allCases.filter { pending[$0] != nil })
        return "runs[\(runs)] overlaps=\(overlapCount) awake[\(awake)] waiting[\(waiting)]"
    }
}
