//
//  PlanSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// LayoutSolver.planSectionOrder, saveSectionOrder's position-preserving rebuild.
/// Closed-app entries are spliced in next to surviving neighbours instead of
/// being appended to the end.
@Suite("Plan section order")
struct PlanSectionOrderTests {
    /// saved=[A,B,C,D,E] with B closed keeps B between A and C.
    @Test("A closed app keeps its mid-list position")
    func closedAppPreservedAtMidIndex() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "C", "D", "E"],
            oldSavedForSection: ["A", "B", "C", "D", "E"],
            allCurrentIdentifiers: ["A", "C", "D", "E"],
            // B is closed, so it is absent from the current-cache set.
            allCurrentBaseIdentifiers: ["A", "C", "D", "E"]
        )

        #expect(result == ["A", "B", "C", "D", "E"],
                "B should be preserved at its old position between A and C")
    }

    /// The forward scan finds B as successor and inserts A before it.
    @Test("A closed app at the head stays at the head")
    func closedAppPreservedAtIndexZero() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["B", "C"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["B", "C"],
            allCurrentBaseIdentifiers: ["B", "C"]
        )

        #expect(result == ["A", "B", "C"])
    }

    /// No successor, so it goes after the predecessor B.
    @Test("A closed app at the tail stays at the tail")
    func closedAppPreservedAtLastIndex() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "B"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["A", "B"],
            allCurrentBaseIdentifiers: ["A", "B"]
        )

        #expect(result == ["A", "B", "C"])
    }

    @Test("Several closed apps all keep their positions")
    func multipleClosedApps() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "C", "E"],
            oldSavedForSection: ["A", "B", "C", "D", "E"],
            allCurrentIdentifiers: ["A", "C", "E"],
            allCurrentBaseIdentifiers: ["A", "C", "E"]
        )

        #expect(result == ["A", "B", "C", "D", "E"])
    }

    /// saved=[A,B,C], cache has X between A and B, giving [A,X,B,C].
    @Test("A newly appeared item lands where the cache puts it")
    func newItemEnters() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "X", "B", "C"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["A", "X", "B", "C"],
            allCurrentBaseIdentifiers: ["A", "X", "B", "C"]
        )

        #expect(result == ["A", "X", "B", "C"])
    }

    /// B is in the cache, just in another section, so it leaves this section's order.
    @Test("An item that moved to another section is dropped")
    func itemMovedToAnotherSectionIsDropped() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "C"],
            oldSavedForSection: ["A", "B", "C"],
            allCurrentIdentifiers: ["A", "B", "C"], // B is in cache, just elsewhere
            allCurrentBaseIdentifiers: ["A", "B", "C"]
        )

        #expect(result == ["A", "C"], "B moved sections → drop from this section's saved order")
    }

    /// saved has com.x:Title:0, cache has com.x:Title:5, so the stale :0 is dropped.
    @Test("A stale instance index is dropped in favour of the live one")
    func staleInstanceIndexIsDropped() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["com.x:Title:5"],
            oldSavedForSection: ["com.x:Title:0"],
            allCurrentIdentifiers: ["com.x:Title:5"], // :0 not present
            allCurrentBaseIdentifiers: ["com.x:Title"] // baseID present
        )

        #expect(result == ["com.x:Title:5"], "stale :0 entry should be dropped, :5 kept")
    }

    @Test("An empty saved order returns the current order")
    func emptyOldSavedReturnsCurrent() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["A", "B"],
            oldSavedForSection: [],
            allCurrentIdentifiers: ["A", "B"],
            allCurrentBaseIdentifiers: ["A", "B"]
        )

        #expect(result == ["A", "B"])
    }

    /// Cursor was saved between Discord and Alter, then quit; the next save keeps it there.
    @Test("A quit app stays between the neighbours it was saved between")
    func cursorScenarioPreservesBetweenDiscordAndAlter() {
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
        // Cursor is closed, so it is not in current.
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

        #expect(
            result == [
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
