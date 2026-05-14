//
//  PlanWithinSectionReorderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for MenuBarItemManager.planWithinSectionReorder.
///
/// Pins down the LCS-based within-section reorder planner. The planner
/// ignores cross-section mismatches (those belong
/// to planRebalanceMove) and treats multi-instance baseIDs as fungible
/// within a section.
final class PlanWithinSectionReorderTests: XCTestCase {
    // MARK: - Helpers

    private func appItem(
        bundleID: String,
        title: String,
        instanceIndex: Int = 0,
        windowID: CGWindowID,
        x: CGFloat
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title, instanceIndex: instanceIndex),
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22)
        )
    }

    // MARK: - Scenarios

    /// All sections already match their saved order → nil.
    func testAllSectionsMatchReturnsNil() {
        let a = appItem(bundleID: "com.a.app", title: "A", windowID: 1001, x: 100)
        let b = appItem(bundleID: "com.b.app", title: "B", windowID: 1002, x: 200)

        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "com.b.app:B"],
        ]

        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [a, b],
            sectionByWindowID: [a.windowID: .visible, b.windowID: .visible],
            savedSectionOrder: saved,
            activelyShownTags: [],
            hasAlwaysHiddenSection: true
        )

        XCTAssertNil(result)
    }

    /// A two-item swap within the visible section produces one move.
    /// Saved=[A,B], current (by minX)=[B,A]. LCS tie-break returns one of
    /// {A} or {B}; either way one item is moved with an anchor reference
    /// to the other.
    func testSingleSwapWithinVisible() {
        let a = appItem(bundleID: "com.a.app", title: "A", windowID: 1010, x: 200)
        let b = appItem(bundleID: "com.b.app", title: "B", windowID: 1011, x: 100)

        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "com.b.app:B"],
        ]

        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [a, b],
            sectionByWindowID: [a.windowID: .visible, b.windowID: .visible],
            savedSectionOrder: saved,
            activelyShownTags: [],
            hasAlwaysHiddenSection: true
        )

        XCTAssertNotNil(result)
        // Exact uid moved and exact anchor are LCS-tie-break-dependent.
        // The test pins down that one item (A or B) is moved with the
        // other as an anchor.
        if case let .leftOfUID(anchor) = result?.destination {
            XCTAssertTrue(["com.a.app:A", "com.b.app:B"].contains(anchor))
        } else if case let .rightOfUID(anchor) = result?.destination {
            XCTAssertTrue(["com.a.app:A", "com.b.app:B"].contains(anchor))
        } else {
            XCTFail("expected leftOfUID or rightOfUID, got \(String(describing: result?.destination))")
        }
    }

    /// Cross-section mismatches are deliberately not the planner's job.
    /// Saved visible=[A], hidden=[B]; current has them in opposite sections.
    /// Count mismatch: planner skips both sections (no items in section
    /// overlap with saved set).
    func testCrossSectionMismatchReturnsNil() {
        let a = appItem(bundleID: "com.a.app", title: "A", windowID: 1020, x: 200)
        let b = appItem(bundleID: "com.b.app", title: "B", windowID: 1021, x: 500)

        let saved: [String: [String]] = [
            "visible": ["com.a.app:A"],
            "hidden": ["com.b.app:B"],
        ]

        // A is currently in hidden (saved to visible), B is currently in
        // visible (saved to hidden). Each section's intersection with
        // saved is empty → planner skips.
        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [a, b],
            sectionByWindowID: [a.windowID: .hidden, b.windowID: .visible],
            savedSectionOrder: saved,
            activelyShownTags: [],
            hasAlwaysHiddenSection: true
        )

        XCTAssertNil(result,
                     "cross-section mismatch should be ignored — planRebalanceMove owns that")
    }

    /// Multi-instance baseIDs are excluded from the reorder comparison.
    /// Saved visible=[app:0, app:1, other], current=[app:1, app:0, other]
    /// (apps swapped). The fungibility rule treats this as a no-op.
    func testMultiInstanceFungibilityWithinSection() {
        let app0 = appItem(bundleID: "com.x.app", title: "Status", instanceIndex: 0, windowID: 1030, x: 200)
        let app1 = appItem(bundleID: "com.x.app", title: "Status", instanceIndex: 1, windowID: 1031, x: 100)
        let other = appItem(bundleID: "com.y.app", title: "Other", windowID: 1032, x: 300)

        let saved: [String: [String]] = [
            "visible": ["com.x.app:Status", "com.x.app:Status:1", "com.y.app:Other"],
        ]

        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [app0, app1, other],
            sectionByWindowID: [app0.windowID: .visible, app1.windowID: .visible, other.windowID: .visible],
            savedSectionOrder: saved,
            activelyShownTags: [],
            hasAlwaysHiddenSection: true
        )

        XCTAssertNil(result,
                     "multi-instance app order within a section is fungible — should not trigger a reorder")
    }

    /// Items in current but not in saved are ignored.
    /// Saved=[A, B], current=[A, B, unknown] in correct relative order
    /// → no reorder.
    func testItemsInCurrentNotInSavedAreIgnored() {
        let a = appItem(bundleID: "com.a.app", title: "A", windowID: 1040, x: 100)
        let b = appItem(bundleID: "com.b.app", title: "B", windowID: 1041, x: 200)
        let unknown = appItem(bundleID: "com.unknown.app", title: "Mystery", windowID: 1042, x: 300)

        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "com.b.app:B"],
        ]

        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [a, b, unknown],
            sectionByWindowID: [
                a.windowID: .visible,
                b.windowID: .visible,
                unknown.windowID: .visible,
            ],
            savedSectionOrder: saved,
            activelyShownTags: [],
            hasAlwaysHiddenSection: true
        )

        XCTAssertNil(result, "items not in saved order should not drive reorder")
    }

    /// Empty saved section is skipped.
    func testEmptySavedSectionSkipped() {
        let a = appItem(bundleID: "com.a.app", title: "A", windowID: 1050, x: 100)

        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [a],
            sectionByWindowID: [a.windowID: .visible],
            savedSectionOrder: ["hidden": ["com.z.app:Z"]], // no visible saved
            activelyShownTags: [],
            hasAlwaysHiddenSection: true
        )

        // Section is visible (current item), but visible has no saved
        // sequence → skipped. Hidden has a saved sequence but no current
        // items → also skipped. Result is nil.
        XCTAssertNil(result)
    }

    /// An actively-shown item is excluded from the reorder consideration.
    /// Saved=[A, B], current=[B, A] in visible, but A is actively-shown
    /// → planner treats A as absent from current, falls back to LCS over
    /// just B, and returns nil (single-item sequence has no reorder).
    func testActivelyShownItemExcluded() {
        let a = appItem(bundleID: "com.a.app", title: "A", windowID: 1060, x: 200)
        let b = appItem(bundleID: "com.b.app", title: "B", windowID: 1061, x: 100)

        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "com.b.app:B"],
        ]

        let result = MenuBarItemManager.planWithinSectionReorder(
            items: [a, b],
            sectionByWindowID: [a.windowID: .visible, b.windowID: .visible],
            savedSectionOrder: saved,
            activelyShownTags: [a.tag.tagIdentifier],
            hasAlwaysHiddenSection: true
        )

        // With A excluded, only B is in the section's overlap with
        // saved. A single-item sequence has nothing to reorder.
        XCTAssertNil(result)
    }
}
