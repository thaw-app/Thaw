//
//  SystemExtraTakeoverCoordinatorStatusTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import Testing
@testable import Thaw

/// What the coordinator reports before it starts. It is never started here:
/// starting it launches stand-ins and writes the system's own settings.
@MainActor
@Suite("System extra takeover status")
struct SystemExtraTakeoverCoordinatorStatusTests {
    /// Hands the engine a fixed journal and records every save.
    private final class StubJournal: SystemExtraOriginalJournaling {
        let entries: [String: SystemExtraOriginalValue]
        private(set) var saves = 0

        init(entries: [String: SystemExtraOriginalValue]) {
            self.entries = entries
        }

        func load() throws -> [String: SystemExtraOriginalValue] {
            entries
        }

        func save(_: [String: SystemExtraOriginalValue]) throws {
            saves += 1
        }
    }

    @Test("With nothing journaled every item reads off")
    func offWithEmptyJournal() {
        let journal = StubJournal(entries: [:])
        let coordinator = SystemExtraTakeoverCoordinator(journal: journal)
        for item in SystemExtraItem.allCases {
            #expect(coordinator.status(for: item) == .off)
        }
        #expect(journal.saves == 0)
    }

    @Test("An original journaled by an earlier session reads as owed a restore")
    func journaledOriginalIsPending() {
        let journal = StubJournal(entries: [SystemExtraItem.timeMachine.rawValue: .value(1)])
        let coordinator = SystemExtraTakeoverCoordinator(journal: journal)
        let status = coordinator.status(for: .timeMachine)
        #expect(status.phase == .off)
        #expect(status.recoveryPending)
        #expect(!coordinator.status(for: .timer).recoveryPending)
        #expect(!coordinator.status(for: .textInput).recoveryPending)
        #expect(journal.saves == 0)
    }
}
