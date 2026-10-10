//
//  StaleIdentifierLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``StaleIdentifierLedger``: when an identifier that matches nothing
/// stops counting as a position, and when it must not.
///
/// The ledger persists on every write, so the suite uses scratch defaults and
/// is `.serialized` as ``withScratchDefaults(_:)`` requires.
@MainActor
@Suite("Stale identifier ledger", .serialized)
struct StaleIdentifierLedgerTests {
    /// One dead entry in four, exactly at the ledger's unmatched-share ceiling.
    private static let dead = "de.simon.RAMTamer:Item-0"
    private static let live = [
        "de.simon.ramtamer:Item-0",
        "org.p0deje.Maccy:Item-0",
        "eu.exelban.Stats:CPU_bar_chart",
    ]

    private var planned: Set<String> {
        Set(Self.live + [Self.dead])
    }

    /// Runs `count` applies in which only the dead identifier misses.
    private func missDead(_ ledger: StaleIdentifierLedger, times count: Int) {
        for _ in 0 ..< count {
            ledger.recordApply(planned: planned, matched: Set(Self.live))
        }
    }

    // MARK: - Retirement

    /// An app quit for an afternoon comes back before it is written off.
    @Test("An identifier below the threshold is not retired")
    func belowThresholdIsNotRetired() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold - 1)
            #expect(!ledger.isRetired(Self.dead))
            #expect(ledger.retiredIdentifiers.isEmpty)
        }
    }

    @Test("An identifier that reaches the threshold is retired")
    func thresholdRetires() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold)
            #expect(ledger.isRetired(Self.dead))
            #expect(ledger.retiredIdentifiers == [Self.dead])
        }
    }

    /// Announced once, so callers can log it without repeating.
    @Test("Retirement is reported by the apply that causes it, and only that one")
    func retirementIsReportedOnce() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold - 1)

            let retiring = ledger.recordApply(planned: planned, matched: Set(Self.live))
            #expect(retiring == [Self.dead])

            let after = ledger.recordApply(planned: planned, matched: Set(Self.live))
            #expect(after.isEmpty)
            #expect(ledger.isRetired(Self.dead))
        }
    }

    /// A Control Center-hosted item whose owner becomes attributable later must come straight back.
    @Test("One live match clears the count and un-retires the identifier")
    func matchClearsTheVerdict() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold)
            #expect(ledger.isRetired(Self.dead))

            ledger.recordApply(planned: planned, matched: planned)

            #expect(!ledger.isRetired(Self.dead))
            #expect(ledger.retiredIdentifiers.isEmpty)
        }
    }

    /// Consecutive, not cumulative: repeated quit and relaunch never adds up to retirement.
    @Test("Misses interrupted by a match do not accumulate")
    func missesDoNotAccumulateAcrossAMatch() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            for _ in 0 ..< 5 {
                missDead(ledger, times: StaleIdentifierLedger.retirementThreshold - 1)
                ledger.recordApply(planned: planned, matched: planned)
            }
            #expect(!ledger.isRetired(Self.dead))
        }
    }

    // MARK: - Sample quality

    /// Source-PID resolution degrades in bulk. An apply that could not attribute a
    /// third of the bar would retire real items by the dozen.
    @Test("An apply with too many unmatched identifiers is discarded")
    func degradedSampleIsDiscarded() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            let mostlyUnmatched = Set(Self.live.prefix(1))
            for _ in 0 ..< (StaleIdentifierLedger.retirementThreshold * 3) {
                ledger.recordApply(planned: planned, matched: mostlyUnmatched)
            }
            #expect(ledger.retiredIdentifiers.isEmpty)
        }
    }

    /// A discarded sample must not clear counts either, or one degraded pass resets progress.
    @Test("A discarded sample leaves existing counts alone")
    func degradedSampleDoesNotResetCounts() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold - 1)
            ledger.recordApply(planned: planned, matched: [])

            #expect(ledger.recordApply(planned: planned, matched: Set(Self.live)) == [Self.dead])
        }
    }

    @Test("An empty plan records nothing")
    func emptyPlanRecordsNothing() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            #expect(ledger.recordApply(planned: [], matched: []).isEmpty)
            #expect(ledger.retiredIdentifiers.isEmpty)
        }
    }

    /// A UUID namespace changes every session, so its entry is unmatched for unrelated reasons.
    @Test("A UUID-namespaced identifier is never retired")
    func uuidNamespaceIsNeverRetired() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            let uuidUID = "\(UUID().uuidString):Item-0"
            let planned = Set(Self.live + [uuidUID])
            for _ in 0 ..< (StaleIdentifierLedger.retirementThreshold * 2) {
                ledger.recordApply(planned: planned, matched: Set(Self.live))
            }
            #expect(ledger.retiredIdentifiers.isEmpty)
        }
    }

    // MARK: - Pruning

    /// A ghost ahead of a live entry inflates the index `savedPositionByBaseID` reports.
    @Test("Pruning drops retired identifiers and keeps the rest in order")
    func pruningDropsRetiredEntriesInPlace() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold)

            let pruned = ledger.pruning([
                "visible": [Self.live[0], Self.dead, Self.live[1]],
                "hidden": [Self.live[2]],
            ])

            #expect(pruned["visible"] == [Self.live[0], Self.live[1]])
            #expect(pruned["hidden"] == [Self.live[2]])
        }
    }

    @Test("Pruning is a no-op when nothing is retired")
    func pruningIsNoOpWithoutRetirements() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            let order = ["visible": [Self.dead] + Self.live]
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold - 1)
            #expect(ledger.pruning(order) == order)
        }
    }

    // MARK: - Persistence

    @Test("Counts survive a new ledger instance")
    func countsPersistAcrossInstances() throws {
        try withScratchDefaults { _ in
            let first = StaleIdentifierLedger()
            missDead(first, times: StaleIdentifierLedger.retirementThreshold)
            #expect(StaleIdentifierLedger().isRetired(Self.dead))
        }
    }

    @Test("removeAll forgets every verdict")
    func removeAllForgetsEverything() throws {
        try withScratchDefaults { _ in
            let ledger = StaleIdentifierLedger()
            missDead(ledger, times: StaleIdentifierLedger.retirementThreshold)

            ledger.removeAll()

            #expect(ledger.retiredIdentifiers.isEmpty)
            #expect(StaleIdentifierLedger().retiredIdentifiers.isEmpty)
        }
    }
}
