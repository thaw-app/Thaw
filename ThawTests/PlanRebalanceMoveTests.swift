//
//  PlanRebalanceMoveTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.planRebalanceMove.
///
/// Pins down the count-based rebalancing behavior used by
/// restoreItemsToSavedSections so subsequent refactors (further extraction
/// or full unification) can keep the algorithm stable.
///
/// The planner takes a pre-computed sectionByWindowID map so tests can
/// classify synthetic items deterministically without going through the
/// live Window Server.
final class PlanRebalanceMoveTests: XCTestCase {
    // MARK: - Helpers

    private func item(
        bundleID: String,
        title: String,
        instanceIndex: Int = 0,
        windowID: CGWindowID
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title, instanceIndex: instanceIndex),
            windowID: windowID
        )
    }

    // MARK: - Scenarios

    /// Empty saved-section order produces no plan.
    func testEmptySavedSectionOrderReturnsNil() {
        let only = item(bundleID: "com.example.app", title: "Status", windowID: 100)
        let result = LayoutSolver.planRebalanceMove(
            items: [only],
            sectionByWindowID: [only.windowID: .hidden],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: [:],
            activelyShownTags: []
        )
        XCTAssertNil(result)
    }

    /// Items currently in their saved sections produce no plan.
    func testAllItemsInCorrectSectionsReturnsNil() {
        let visibleItem = item(bundleID: "com.example.app", title: "Visible", windowID: 101)
        let hiddenItem = item(bundleID: "com.example.app", title: "Hidden", windowID: 102)
        let ahItem = item(bundleID: "com.example.app", title: "AH", windowID: 103)

        let saved: [String: [String]] = [
            "visible": ["com.example.app:Visible"],
            "hidden": ["com.example.app:Hidden"],
            "alwaysHidden": ["com.example.app:AH"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [visibleItem, hiddenItem, ahItem],
            sectionByWindowID: [
                visibleItem.windowID: .visible,
                hiddenItem.windowID: .hidden,
                ahItem.windowID: .alwaysHidden,
            ],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )
        XCTAssertNil(result)
    }

    /// An item currently visible but saved-as-hidden produces a move from
    /// .visible to .hidden.
    func testSingleMisplacedItemPlansCrossSectionMove() {
        let stray = item(bundleID: "com.example.app", title: "Status", windowID: 200)

        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [stray],
            sectionByWindowID: [stray.windowID: .visible],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.fromSection, .visible)
        XCTAssertEqual(result?.toSection, .hidden)
        XCTAssertEqual(result?.item.windowID, 200)
    }

    /// Two instances of the same baseID, both saved-as-hidden but one
    /// currently visible. The planner picks the visible-side instance to
    /// move into hidden. Multi-instance fungibility means the planner only
    /// cares that the count in each section matches the saved count.
    func testMultiInstanceBaseIDPicksTheMisplacedInstance() {
        let inHidden = item(bundleID: "com.example.app", title: "Status", instanceIndex: 0, windowID: 300)
        let strayInVisible = item(bundleID: "com.example.app", title: "Status", instanceIndex: 1, windowID: 301)

        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status:0", "com.example.app:Status:1"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [inHidden, strayInVisible],
            sectionByWindowID: [
                inHidden.windowID: .hidden,
                strayInVisible.windowID: .visible,
            ],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.fromSection, .visible)
        XCTAssertEqual(result?.toSection, .hidden)
        XCTAssertEqual(result?.item.windowID, 301)
    }

    /// When the always-hidden section is disabled, saved alwaysHidden counts
    /// collapse into hidden. An item currently in visible that was saved-as-
    /// alwaysHidden is restored to hidden, not alwaysHidden.
    func testAlwaysHiddenDisabledMergesIntoHidden() {
        let stray = item(bundleID: "com.example.app", title: "Status", windowID: 400)

        let saved: [String: [String]] = [
            "alwaysHidden": ["com.example.app:Status"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [stray],
            sectionByWindowID: [stray.windowID: .visible],
            hasAlwaysHiddenSection: false,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.toSection, .hidden,
                       "alwaysHidden saved counts should collapse into hidden when no AH control item is present")
        XCTAssertEqual(result?.fromSection, .visible)
    }

    /// Items whose tag is currently in activelyShownTags are excluded from
    /// rebalancing — they were intentionally moved to visible via
    /// temporarilyShow and the rehide flow handles them, not this planner.
    func testActivelyShownTagsAreExcluded() {
        let temporarilyShown = item(bundleID: "com.example.app", title: "Status", windowID: 500)
        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [temporarilyShown],
            sectionByWindowID: [temporarilyShown.windowID: .visible],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: [temporarilyShown.tag.tagIdentifier]
        )

        XCTAssertNil(result,
                     "an actively-shown item should not be eligible for rebalancing — its rehide path owns it")
    }

    // MARK: - Position-aware destination

    /// The cross-section restore destination is now position-aware: a
    /// restored item is anchored against its saved-order neighbors in
    /// the target section, not at the section boundary.
    ///
    /// saved visible=[Cursor, Alter, Claude], current visible=[Alter,
    /// Claude], Cursor is in always-hidden. Restore should plan a move
    /// from always-hidden to visible, anchored .leftOfUID("Alter")
    /// because Alter is Cursor's saved successor.
    func testRebalanceMoveAnchorsLeftOfSuccessor() {
        let alter = item(bundleID: "com.example.alter", title: "Alter", windowID: 1000)
        let claude = item(bundleID: "com.example.claude", title: "Claude", windowID: 1001)
        let cursor = item(bundleID: "com.example.cursor", title: "Cursor", windowID: 1002)

        let saved: [String: [String]] = [
            "visible": [
                "com.example.cursor:Cursor",
                "com.example.alter:Alter",
                "com.example.claude:Claude",
            ],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [alter, claude, cursor],
            sectionByWindowID: [
                alter.windowID: .visible,
                claude.windowID: .visible,
                cursor.windowID: .alwaysHidden,
            ],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.fromSection, .alwaysHidden)
        XCTAssertEqual(result?.toSection, .visible)
        XCTAssertEqual(result?.item.windowID, 1002)
        XCTAssertEqual(result?.destination, .leftOfUID("com.example.alter:Alter"),
                       "saved index 0 with successor present in section → .leftOfUID(successor)")
    }

    /// When the moving item's saved successor is not currently in the
    /// target section, fall back to the predecessor.
    /// saved visible=[A, Cursor, Z], current visible=[A]. Restore plans
    /// .rightOfUID(A) because Z is absent and A is the predecessor.
    func testRebalanceMoveAnchorsRightOfPredecessorWhenNoForwardAnchor() {
        let a = item(bundleID: "com.aa.app", title: "AA", windowID: 1100)
        let cursor = item(bundleID: "com.cursor.app", title: "Cursor", windowID: 1101)

        let saved: [String: [String]] = [
            "visible": [
                "com.aa.app:AA",
                "com.cursor.app:Cursor",
                "com.zz.app:ZZ",
            ],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [a, cursor],
            sectionByWindowID: [
                a.windowID: .visible,
                cursor.windowID: .alwaysHidden,
            ],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.destination, .rightOfUID("com.aa.app:AA"))
    }

    /// When no anchors are present in the target section, fall back to
    /// the section boundary.
    /// saved visible=[X, Cursor], current visible empty, Cursor in
    /// always-hidden → .sectionBoundary(.visible).
    func testRebalanceMoveFallsBackToSectionBoundary() {
        let cursor = item(bundleID: "com.cursor.app", title: "Cursor", windowID: 1200)

        let saved: [String: [String]] = [
            "visible": ["com.x.app:X", "com.cursor.app:Cursor"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [cursor],
            sectionByWindowID: [cursor.windowID: .alwaysHidden],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.destination, .sectionBoundary(.visible))
    }

    /// When a baseID has more current items than saved counts in one
    /// section, surplus is taken from the suffix (rightmost) of the bucket
    /// so the leftmost items stay put. Three instances live in hidden, two
    /// are saved-in-hidden and one is saved-in-visible; the rightmost
    /// (suffix) instance is the one chosen to move.
    func testSurplusSelectionTakesSuffixInstance() {
        // Three instances currently in hidden, presented in left-to-right
        // order so the planner's per-section bucket reflects that order
        // when .suffix is applied.
        let leftmost = item(bundleID: "com.example.app", title: "Status", instanceIndex: 0, windowID: 600)
        let middle = item(bundleID: "com.example.app", title: "Status", instanceIndex: 1, windowID: 601)
        let rightmost = item(bundleID: "com.example.app", title: "Status", instanceIndex: 2, windowID: 602)

        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status:0", "com.example.app:Status:1"],
            "visible": ["com.example.app:Status:2"],
        ]

        let result = LayoutSolver.planRebalanceMove(
            items: [leftmost, middle, rightmost],
            sectionByWindowID: [
                leftmost.windowID: .hidden,
                middle.windowID: .hidden,
                rightmost.windowID: .hidden,
            ],
            hasAlwaysHiddenSection: true,
            savedSectionOrder: saved,
            activelyShownTags: []
        )

        XCTAssertEqual(result?.fromSection, .hidden)
        XCTAssertEqual(result?.toSection, .visible)
        XCTAssertEqual(result?.item.windowID, 602,
                       "surplus selection should pick the rightmost (suffix) instance")
    }
}
