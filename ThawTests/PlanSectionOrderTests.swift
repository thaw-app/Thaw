//
//  PlanSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.planSectionOrder, the
/// position-preserving rebuild used by saveSectionOrder.
///
/// Pins down the fix for the pre-existing bug where closed-app entries
/// were appended to the end of the saved list, destroying user-intended
/// position. Closed entries are now spliced in at positions anchored
/// against their old-neighbor entries that are still present.
final class PlanSectionOrderTests: XCTestCase {
    /// Closed app at mid-index: saved=[A,B,C,D,E], B not present →
    /// new=[A,B,C,D,E] (B's position preserved, anchored against A or C).
    func testClosedAppPreservedAtMidIndex() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "C", "D", "E"],
            oldSavedForSection: ["A", "B", "C", "D", "E"],
            allCurrentIdentifiers: ["A", "C", "D", "E"],
            // B is closed: it should NOT appear in allCurrentBaseIdentifiers
            // because that set tracks currently-cached items only.
            allCurrentBaseIdentifiers: ["A", "C", "D", "E"]
        )

        XCTAssertEqual(result, ["A", "B", "C", "D", "E"],
                       "B should be preserved at its old position between A and C")
    }

    /// Closed app at index 0: saved=[A,B,C], A closed → new=[A,B,C].
    /// A is preserved at the start because forward scan finds B as
    /// successor, inserts before B.
    func testClosedAppPreservedAtIndexZero() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["B", "C"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["B", "C"],
            allCurrentBaseIdentifiers: ["B", "C"]
        )

        XCTAssertEqual(result, ["A", "B", "C"])
    }

    /// Closed app at last index: saved=[A,B,C], C closed → new=[A,B,C].
    /// Forward scan from C finds nothing; backward finds B → insert
    /// after B.
    func testClosedAppPreservedAtLastIndex() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "B"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["A", "B"],
            allCurrentBaseIdentifiers: ["A", "B"]
        )

        XCTAssertEqual(result, ["A", "B", "C"])
    }

    /// Multiple closed apps: saved=[A,B,C,D,E], B and D closed →
    /// new=[A,B,C,D,E]. Both closed entries get their positions
    /// preserved.
    func testMultipleClosedApps() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "C", "E"],
            oldSavedForSection: ["A", "B", "C", "D", "E"],
            allCurrentIdentifiers: ["A", "C", "E"],
            allCurrentBaseIdentifiers: ["A", "C", "E"]
        )

        XCTAssertEqual(result, ["A", "B", "C", "D", "E"])
    }

    /// New item enters: saved=[A,B,C], current cache has X between A
    /// and B → new=[A,X,B,C]. The new item X gets the leading position
    /// from current cache; the saved order's items keep their relative
    /// order through closed-app preservation.
    func testNewItemEnters() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "X", "B", "C"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["A", "X", "B", "C"],
            allCurrentBaseIdentifiers: ["A", "X", "B", "C"]
        )

        XCTAssertEqual(result, ["A", "X", "B", "C"])
    }

    /// Section move: saved-in-this-section=[A,B,C], B currently in
    /// ANOTHER section. allCurrentIdentifiers contains B (because it
    /// IS in the cache, just elsewhere). The planner drops B from
    /// this section's saved order.
    func testItemMovedToAnotherSectionIsDropped() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "C"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["A", "B", "C"], // B is in cache, just elsewhere
            allCurrentBaseIdentifiers: ["A", "B", "C"]
        )

        XCTAssertEqual(result, ["A", "C"], "B moved sections → drop from this section's saved order")
    }

    /// Stale instance index: saved=[com.x:Title:0], current has
    /// com.x:Title:5 (instance index shifted). allCurrentBaseIdentifiers
    /// contains "com.x:Title". The planner drops the stale :0 entry
    /// because the baseID exists with a different instance.
    func testStaleInstanceIndexIsDropped() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["com.x:Title:5"],
            oldSavedForSection: ["com.x:Title:0"],
            allCurrentIdentifiers: ["com.x:Title:5"], // :0 not present
            allCurrentBaseIdentifiers: ["com.x:Title"] // baseID present
        )

        XCTAssertEqual(result, ["com.x:Title:5"], "stale :0 entry should be dropped, :5 kept")
    }

    /// Empty old saved: just returns current.
    func testEmptyOldSavedReturnsCurrent() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "B"],
            oldSavedForSection: [],
            allCurrentIdentifiers: ["A", "B"],
            allCurrentBaseIdentifiers: ["A", "B"]
        )

        XCTAssertEqual(result, ["A", "B"])
    }

    /// The user's actual Cursor scenario: Cursor was at index 2 in
    /// saved (between Discord and Alter), then quit. After A.7's fix,
    /// the next save preserves Cursor at index 2.
    func testCursorScenarioPreservesBetweenDiscordAndAlter() {
        // Approximation: Droppy, Discord, Cursor, Alter, ..., Battery, BentoBox, Clock.
        let oldSaved = [
            "iordv.Droppy:Item-0",
            "com.hnc.Discord:Item",
            "com.todesktop.230313mzl4w4u92:Item-0", // Cursor at index 2
            "com.wearedevx.alter:Item-0",
            "com.apple.controlcenter:Battery",
            "com.apple.controlcenter:BentoBox-0",
            "com.apple.controlcenter:Clock",
        ]
        // Cursor is closed → not in current.
        let current = [
            "iordv.Droppy:Item-0",
            "com.hnc.Discord:Item",
            "com.wearedevx.alter:Item-0",
            "com.apple.controlcenter:Battery",
            "com.apple.controlcenter:BentoBox-0",
            "com.apple.controlcenter:Clock",
        ]
        let allCurrentIdentifiers = Set(current)
        let allCurrentBaseIdentifiers = Set(current.map {
            $0.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
        })

        let result = LayoutSolver.planSectionOrder(
            currentInSection: current,
            oldSavedForSection: oldSaved,
            allCurrentIdentifiers: allCurrentIdentifiers,
            allCurrentBaseIdentifiers: allCurrentBaseIdentifiers
        )

        XCTAssertEqual(
            result,
            [
                "iordv.Droppy:Item-0",
                "com.hnc.Discord:Item",
                "com.todesktop.230313mzl4w4u92:Item-0", // Cursor preserved at index 2
                "com.wearedevx.alter:Item-0",
                "com.apple.controlcenter:Battery",
                "com.apple.controlcenter:BentoBox-0",
                "com.apple.controlcenter:Clock",
            ],
            "the position-preservation fix: Cursor stays between Discord and Alter after quit"
        )
    }
}
