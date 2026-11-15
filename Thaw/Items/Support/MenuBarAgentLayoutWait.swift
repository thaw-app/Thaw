//
//  MenuBarAgentLayoutWait.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// The poll that follows a preferred-position write, and what its result says about the write.
///
/// A write is only a request: MenuBarAgent either re-sorts the bar, or drops it. The poll
/// watches the bar until the caller's check passes or a deadline runs out, and records
/// whether anything shifted, which is what tells a dropped write from a slow one. The
/// verdict functions turn that result into the decision the caller acts on, so the caller
/// only reads the bar, writes, and logs.
enum MenuBarAgentLayoutWait {
    /// The outcome of one poll loop.
    struct Result {
        /// The most recent enumeration.
        let items: [MenuBarItem]
        /// Whether any item's origin shifted while polling. false means
        /// MenuBarAgent never acted on the write at all.
        let barMoved: Bool
        /// A cancelled wait proves nothing about the agent, so it is not a refusal.
        let cancelled: Bool
        let observationUnavailable: Bool
    }

    /// Waits for the agent to re-sort after a write, until isSatisfied or the
    /// deadline. A wall-clock deadline, since each poll costs an AX walk, and
    /// waits in one move can share it. barMoved says whether the bar reacted.
    ///
    /// - Parameters:
    ///   - deadline: When to stop polling. When nil, fallbackDeadline is asked
    ///     once the first enumeration is in, because that read can take seconds.
    ///   - interval: How long to sleep between enumerations.
    ///   - earlyBailProbe: If nothing has moved this long after the first read, the
    ///     agent dropped the write and the wait ends. Once anything moves, the
    ///     wait runs its course.
    ///   - now: The clock the deadlines are read against.
    ///   - sleep: Waits between polls. A throw ends the wait as cancelled.
    ///   - enumerate: Reads the bar; nil means the read was unavailable.
    ///   - isSatisfied: Whether the bar already shows the write.
    static func run(
        deadline: ContinuousClock.Instant? = nil,
        fallbackDeadline: () -> ContinuousClock.Instant,
        interval: Duration,
        earlyBailProbe: Duration? = nil,
        now: () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        enumerate: () async -> [MenuBarItem]?,
        isSatisfied: ([MenuBarItem]) -> Bool
    ) async -> Result {
        guard var liveItems = await enumerate() else {
            return Result(
                items: [], barMoved: false, cancelled: Task.isCancelled, observationUnavailable: true
            )
        }
        let deadline = deadline ?? fallbackDeadline()
        let originalGeometry = LayoutWaitGeometry.layoutGeometrySignature(liveItems)
        var barMoved = false
        // If nothing moved by earlyBailProbe the agent dropped the write.
        // Once anything moves, barMoved latches and the wait runs its course.
        let earlyBailDeadline = earlyBailProbe.map { now() + $0 }

        // Check the existing walk first, so an instantly honored write costs
        // no sleep and no second walk.
        if isSatisfied(liveItems) {
            return Result(
                items: liveItems, barMoved: false, cancelled: false, observationUnavailable: false
            )
        }

        while now() < deadline {
            do {
                try await sleep(interval)
            } catch {
                // try? here would spin AX walks and escalate a healthy write
                // to a drag.
                return Result(
                    items: liveItems,
                    barMoved: barMoved,
                    cancelled: true,
                    observationUnavailable: false
                )
            }
            guard let observedItems = await enumerate() else {
                return Result(
                    items: [], barMoved: barMoved, cancelled: Task.isCancelled, observationUnavailable: true
                )
            }
            liveItems = observedItems
            if !barMoved, LayoutWaitGeometry.layoutGeometryChanged(
                from: originalGeometry,
                to: LayoutWaitGeometry.layoutGeometrySignature(liveItems)
            ) {
                barMoved = true
            }
            if isSatisfied(liveItems) {
                break
            }
            // Nothing has shifted by the probe window: the agent dropped the
            // write. Stop here rather than watching a frozen bar for the rest
            // of the deadline.
            if !barMoved, let earlyBailDeadline, now() >= earlyBailDeadline {
                break
            }
        }
        return Result(
            items: liveItems, barMoved: barMoved, cancelled: false, observationUnavailable: false
        )
    }

    // MARK: Verdicts

    /// What a wait says about a single-item move's write.
    enum MoveVerdict: Equatable {
        /// The bar could not be read, so the write was neither seen nor refused.
        case observationUnavailable
        /// The bar shows the move.
        case verified
        /// The bar never shifted, so the agent dropped the write.
        case agentIgnored
        /// The bar moved but does not show the move, so a refreshed write may still land it.
        case unsatisfied
    }

    /// Judges a wait that followed a single-item move's write.
    ///
    /// An unreadable bar comes first, since there is nothing to check against.
    /// isSatisfied is asked only when the bar was read.
    static func moveVerdict(of result: Result, isSatisfied: () -> Bool) -> MoveVerdict {
        if result.observationUnavailable {
            return .observationUnavailable
        }
        if isSatisfied() {
            return .verified
        }
        return result.barMoved ? .unsatisfied : .agentIgnored
    }

    /// What a wait says about a batch order write.
    enum ResortVerdict: Equatable {
        /// The bar shows the order.
        case satisfied
        /// The bar never shifted and the nudge ran, so the agent dropped the write.
        case agentIgnored
        /// The bar never shifted, but no nudge ran: the write was never given a chance to be seen.
        case unverified
        /// The bar moved, or the wait was cancelled: nothing to conclude.
        case inconclusive
    }

    /// Judges a wait that followed a batch order write.
    ///
    /// A satisfied bar wins over every other reading. A cancelled wait proves
    /// nothing about the agent, and a write without a nudge is only evidence
    /// when the nudge actually ran.
    static func resortVerdict(of result: Result, satisfied: Bool, nudgeRan: Bool) -> ResortVerdict {
        if satisfied {
            return .satisfied
        }
        guard !result.barMoved, !result.cancelled else {
            return .inconclusive
        }
        return nudgeRan ? .agentIgnored : .unverified
    }

    /// The deadline for the retry's wait. It shares the phase budget, but never
    /// leaves the retry with fewer than three polls: if the first wait consumed
    /// the window, a second write issued and never observed is worse than not
    /// retrying.
    static func retryDeadline(
        phaseDeadline: ContinuousClock.Instant,
        now: ContinuousClock.Instant,
        pollInterval: Duration
    ) -> ContinuousClock.Instant {
        max(phaseDeadline, now + pollInterval * 3)
    }
}
