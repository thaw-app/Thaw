//
//  DisplaySettingsManagerSpacingGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

@testable import Thaw
import XCTest

@MainActor
final class DisplaySettingsManagerSpacingGateTests: XCTestCase {

    // MARK: - Predicate

    func testPredicateSkipsWhenUUIDsMatch() {
        XCTAssertTrue(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-A",
            lastAppliedActiveDisplayUUID: "UUID-A"
        ))
    }

    func testPredicateDoesNotSkipWhenUUIDsDiffer() {
        XCTAssertFalse(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-B",
            lastAppliedActiveDisplayUUID: "UUID-A"
        ))
    }

    func testPredicateDoesNotSkipOnFirstApply() {
        XCTAssertFalse(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-A",
            lastAppliedActiveDisplayUUID: nil
        ))
    }

    func testPredicateDoesNotSkipWhenCurrentBecomesNil() {
        XCTAssertFalse(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: nil,
            lastAppliedActiveDisplayUUID: "UUID-A"
        ))
    }

    func testPredicateSkipsWhenBothNil() {
        XCTAssertTrue(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: nil,
            lastAppliedActiveDisplayUUID: nil
        ))
    }

    func testPredicateIsStableAcrossRepeatedCalls() {
        for _ in 0..<10 {
            XCTAssertTrue(DisplaySettingsManager.shouldSkipSpacingApply(
                currentActiveDisplayUUID: "UUID-A",
                lastAppliedActiveDisplayUUID: "UUID-A"
            ))
        }
    }

    // MARK: - Field semantics

    func testFreshManagerHasNilLastAppliedUUID() {
        let manager = DisplaySettingsManager()
        XCTAssertNil(manager.lastAppliedActiveDisplayUUID)
    }

    func testSeededFieldDrivesPredicate() {
        let manager = DisplaySettingsManager()
        manager.lastAppliedActiveDisplayUUID = "UUID-A"

        XCTAssertTrue(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-A",
            lastAppliedActiveDisplayUUID: manager.lastAppliedActiveDisplayUUID
        ))
        XCTAssertFalse(DisplaySettingsManager.shouldSkipSpacingApply(
            currentActiveDisplayUUID: "UUID-B",
            lastAppliedActiveDisplayUUID: manager.lastAppliedActiveDisplayUUID
        ))
    }
}
