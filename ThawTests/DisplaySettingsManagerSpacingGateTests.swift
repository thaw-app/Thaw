//
//  DisplaySettingsManagerSpacingGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Display settings manager spacing gate", .serialized)
struct DisplaySettingsManagerSpacingGateTests {
    // MARK: - Predicate

    @Test("Matching display UUIDs skip the spacing apply")
    func predicateSkipsWhenUUIDsMatch() {
        #expect(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-A",
            lastAppliedActiveDisplayUUID: "UUID-A"
        ))
    }

    @Test("Differing display UUIDs do not skip the spacing apply")
    func predicateDoesNotSkipWhenUUIDsDiffer() {
        #expect(!DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-B",
            lastAppliedActiveDisplayUUID: "UUID-A"
        ))
    }

    @Test("The first apply is never skipped")
    func predicateDoesNotSkipOnFirstApply() {
        #expect(!DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-A",
            lastAppliedActiveDisplayUUID: nil
        ))
    }

    @Test("An apply is not skipped once the current UUID becomes nil")
    func predicateDoesNotSkipWhenCurrentBecomesNil() {
        #expect(!DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: nil,
            lastAppliedActiveDisplayUUID: "UUID-A"
        ))
    }

    @Test("Two nil UUIDs skip the spacing apply")
    func predicateSkipsWhenBothNil() {
        #expect(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: nil,
            lastAppliedActiveDisplayUUID: nil
        ))
    }

    @Test("The predicate answers the same way on repeated calls")
    func predicateIsStableAcrossRepeatedCalls() {
        for _ in 0 ..< 10 {
            #expect(DisplaySettingsManager.shouldSkipSpacingApply(
                currentActiveDisplayUUID: "UUID-A",
                lastAppliedActiveDisplayUUID: "UUID-A"
            ))
        }
    }

    // MARK: - Field semantics

    @Test("A fresh manager has no last-applied display UUID")
    func freshManagerHasNilLastAppliedUUID() {
        let manager = DisplaySettingsManager()
        #expect(manager.lastAppliedActiveDisplayUUID == nil)
    }

    @Test("The seeded field drives the predicate")
    func seededFieldDrivesPredicate() {
        let manager = DisplaySettingsManager()
        manager.lastAppliedActiveDisplayUUID = "UUID-A"

        #expect(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-A",
            lastAppliedActiveDisplayUUID: manager.lastAppliedActiveDisplayUUID
        ))
        #expect(!DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-B",
            lastAppliedActiveDisplayUUID: manager.lastAppliedActiveDisplayUUID
        ))
    }
}
