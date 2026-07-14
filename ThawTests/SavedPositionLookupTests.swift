//
//  SavedPositionLookupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for the savedPosition lookup helpers used by
/// the position-aware restore and unmanaged-placement work.
final class SavedPositionLookupTests: XCTestCase {
    func testSavedSectionKeepsSplitInstancesInTheirOwnSections() {
        let saved = [
            "visible": ["com.example.app:Status"],
            "hidden": ["com.example.app:Status:1"],
        ]

        XCTAssertEqual(
            MenuBarItemManager.savedSection(
                forIdentifier: "com.example.app:Status",
                in: saved
            ),
            .visible
        )
        XCTAssertEqual(
            MenuBarItemManager.savedSection(
                forIdentifier: "com.example.app:Status:1",
                in: saved
            ),
            .hidden
        )
        XCTAssertNil(
            MenuBarItemManager.savedSection(
                forIdentifier: "com.example.app:Status:5",
                in: saved
            ),
            "A changed suffix must not choose one of two intentionally split sections."
        )
    }

    // MARK: - savedPosition (exact match)

    /// An identifier present in a saved section returns its (section, index).
    func testExactMatchInVisibleSection() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status", "com.other.app:Item"],
            "hidden": ["com.example.app:Helper"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.other.app:Item",
            in: saved
        )
        XCTAssertEqual(result, LayoutSolver.SavedPosition(section: .visible, index: 1))
    }

    /// An identifier present in the hidden section returns .hidden.
    func testExactMatchInHiddenSection() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
            "hidden": ["com.example.app:Helper"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.example.app:Helper",
            in: saved
        )
        XCTAssertEqual(result, LayoutSolver.SavedPosition(section: .hidden, index: 0))
    }

    /// An identifier not in any saved section returns nil.
    func testIdentifierNotFound() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.absent.app:Missing",
            in: saved
        )
        XCTAssertNil(result)
    }

    /// Empty savedSectionOrder returns nil.
    func testEmptySavedSectionOrder() {
        let result = LayoutSolver.savedPosition(for: "anything", in: [:])
        XCTAssertNil(result)
    }

    /// Multi-instance: identifier app:Status:1 matches its exact saved
    /// entry even when app:Status:0 also exists.
    func testMultiInstanceExactMatch() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status", "com.example.app:Status:1", "com.example.app:Status:2"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.example.app:Status:1",
            in: saved
        )
        XCTAssertEqual(result, LayoutSolver.SavedPosition(section: .visible, index: 1))
    }

    // MARK: - savedPositionByBaseID (baseID fallback)

    /// An exact match wins over a baseID fallback.
    func testBaseIDFallbackExactMatchPreferred() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status", "com.example.app:Status:1"],
        ]
        let result = LayoutSolver.savedPositionByBaseID(
            for: "com.example.app:Status:1",
            in: saved
        )
        XCTAssertEqual(result, LayoutSolver.SavedPosition(section: .visible, index: 1),
                       "exact :1 match should win even though :0 (no suffix) shares the baseID")
    }

    /// A relaunched instance with a different :N suffix finds a saved
    /// slot via baseID match.
    func testBaseIDFallbackForInstanceDrift() {
        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status", "com.example.app:Status:1"],
        ]
        // A new instance shows up as :5 (e.g. spurious instanceIndex from
        // ordering churn). The exact match fails; baseID fallback returns
        // the first saved instance.
        let result = LayoutSolver.savedPositionByBaseID(
            for: "com.example.app:Status:5",
            in: saved,
            knownBaseIdentifiers: ["com.example.app:Status"]
        )
        XCTAssertEqual(result, LayoutSolver.SavedPosition(section: .hidden, index: 0),
                       "baseID fallback should return the first matching saved instance")
    }

    func testBaseIDFallbackRejectsInstancesSplitAcrossSections() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
            "hidden": ["com.example.app:Status:1"],
        ]

        XCTAssertNil(
            LayoutSolver.savedPositionByBaseID(
                for: "com.example.app:Status:5",
                in: saved,
                knownBaseIdentifiers: ["com.example.app:Status"]
            ),
            "A changed suffix must not arbitrarily move a split instance into one saved section."
        )
    }

    func testBaseIDFallbackKeepsColonBearingTitlesDistinct() {
        let saved = [
            "visible": ["com.example.app:CPU: 10%:1"],
            "hidden": ["com.example.app:CPU: 20%:1"],
        ]

        XCTAssertEqual(
            LayoutSolver.savedPositionByBaseID(
                for: "com.example.app:CPU: 20%:2",
                in: saved,
                knownBaseIdentifiers: ["com.example.app:CPU: 10%", "com.example.app:CPU: 20%"]
            ),
            LayoutSolver.SavedPosition(section: .hidden, index: 0)
        )
    }

    func testBaseIDFallbackKeepsNumericColonTitleDistinctFromPrefixItem() {
        let saved = [
            "visible": ["com.example.app:Meeting"],
            "hidden": ["com.example.app:Meeting:30"],
        ]

        XCTAssertEqual(
            LayoutSolver.savedPositionByBaseID(
                for: "com.example.app:Meeting:30",
                in: saved,
                knownBaseIdentifiers: ["com.example.app:Meeting", "com.example.app:Meeting:30"]
            ),
            LayoutSolver.SavedPosition(section: .hidden, index: 0)
        )
    }

    /// Malformed identifier with no colon never matches.
    func testMalformedIdentifierNeverMatches() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
        ]
        let result = LayoutSolver.savedPositionByBaseID(
            for: "no-colon-here",
            in: saved
        )
        XCTAssertNil(result)
    }
}
