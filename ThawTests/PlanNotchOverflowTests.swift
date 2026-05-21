//
//  PlanNotchOverflowTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.planNotchOverflow.
///
/// Pins down the tiered priority overflow algorithm used by
/// applyProfileLayout: unmanaged items overflow before profile items,
/// and within each tier leftmost items overflow first. Locks in the
/// May 13 fixes: no double-counted spacing, no per-item subtraction
/// inside the planner.
///
/// The planner is pure arithmetic over its inputs (no Bridging or
/// NSScreen access). Tests construct synthetic input directly.
final class PlanNotchOverflowTests: XCTestCase {
    // MARK: - Helpers

    /// Build a desiredFiltered sequence for: chevron + visible profile
    /// items + unmanaged + hiddenCtrl + (optional hidden items) + ahCtrl
    /// + (optional AH items). Caller specifies the visible-side order.
    private func makeSequence(
        chevron: String?,
        visible: [String],
        hiddenCtrl: String,
        hidden: [String] = [],
        ahCtrl: String?,
        alwaysHidden: [String] = []
    ) -> [String] {
        var result = [String]()
        if let chevron { result.append(chevron) }
        result.append(contentsOf: visible)
        result.append(hiddenCtrl)
        result.append(contentsOf: hidden)
        if let ahCtrl { result.append(ahCtrl) }
        result.append(contentsOf: alwaysHidden)
        return result
    }

    private let chevron = "thaw:VisibleControlItem"
    private let hiddenCtrl = "thaw:HiddenControlItem"
    private let ahCtrl = "thaw:AlwaysHiddenControlItem"

    // MARK: - Scenarios

    /// When the profile fits and there are no unmanaged items, overflow
    /// is empty and inputs pass through unchanged.
    func testProfileFitsNoUnmanagedNoOverflow() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b", "c"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "c": 24]
        let sectionMap = ["a": "visible", "b": "visible", "c": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 200 // plenty of room
        )

        XCTAssertEqual(result.overflowUIDs, [])
        XCTAssertEqual(result.updatedDesiredFiltered, desired)
        XCTAssertEqual(result.updatedSectionMap, sectionMap)
    }

    /// Profile fits, unmanaged also fits — no overflow.
    func testProfileFitsUnmanagedFitsNoOverflow() {
        // chevron(24) + a(24) + b(24) + u1(24) + u2(24) = 120
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b", "u1", "u2"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "u1": 24, "u2": 24]
        let sectionMap = ["a": "visible", "b": "visible", "u1": "visible", "u2": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: ["u1", "u2"],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 130 // fits 120
        )

        XCTAssertEqual(result.overflowUIDs, [])
    }

    /// Profile fits, but unmanaged doesn't — overflow only unmanaged,
    /// leftmost-first (chevron-side first).
    func testProfileFitsUnmanagedOverflowsLeftmostFirst() {
        // chevron(24) + a(24) + u1(24) + u2(24) = 96
        // Available 90: u1 overflows (leftmost of unmanaged), u2 stays.
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "u1", "u2"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "u1": 24, "u2": 24]
        let sectionMap = ["a": "visible", "u1": "visible", "u2": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: ["u1", "u2"],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 90
        )

        XCTAssertEqual(result.overflowUIDs, ["u1"])
        XCTAssertEqual(result.updatedSectionMap["u1"], "hidden")
        XCTAssertEqual(result.updatedSectionMap["u2"], "visible")
        XCTAssertEqual(result.updatedSectionMap["a"], "visible")
    }

    /// Profile baseline exceeds the budget: all unmanaged overflow,
    /// then profile leftmost overflows until the remainder fits.
    func testProfileBaselineExceedsBudgetOverflowsAllUnmanagedThenLeftmostProfile() {
        // chevron(24) + p1(24) + p2(24) + p3(24) + u1(24) = 120
        // Available 70: profileBaseline = 24 + 24 + 24 + 24 = 96 > 70.
        // All unmanaged overflow (u1).
        // From CC end, fit profile items: chevron(24) + p3(24) = 48 <= 70 ✓
        //                                  + p2(24) = 72 > 70 ✗
        // p3 fits, p2 and p1 overflow.
        let desired = makeSequence(
            chevron: chevron,
            visible: ["p1", "p2", "p3", "u1"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [
            chevron: 24, "p1": 24, "p2": 24, "p3": 24, "u1": 24,
        ]
        let sectionMap = ["p1": "visible", "p2": "visible", "p3": "visible", "u1": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: ["u1"],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 70
        )

        XCTAssertEqual(Set(result.overflowUIDs), Set(["u1", "p1", "p2"]))
        XCTAssertEqual(result.updatedSectionMap["u1"], "hidden")
        XCTAssertEqual(result.updatedSectionMap["p1"], "hidden")
        XCTAssertEqual(result.updatedSectionMap["p2"], "hidden")
        XCTAssertEqual(result.updatedSectionMap["p3"], "visible")
    }

    /// When chevron width alone equals the budget, all other items
    /// overflow (regardless of tier).
    func testChevronEqualsBudgetEverythingOverflows() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["p1", "u1"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "p1": 24, "u1": 24]
        let sectionMap = ["p1": "visible", "u1": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: ["u1"],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24
        )

        XCTAssertEqual(Set(result.overflowUIDs), Set(["p1", "u1"]))
    }

    /// When the always-hidden control item is absent, overflowed items
    /// append into the hidden section only — no AH section to consider.
    func testAlwaysHiddenAbsentOverflowGoesToHidden() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["u1"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: nil
        )
        let widths: [String: CGFloat] = [chevron: 24, "u1": 24]
        let sectionMap = ["u1": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: ["u1"],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: nil
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24 // only chevron fits
        )

        XCTAssertEqual(result.overflowUIDs, ["u1"])
        XCTAssertEqual(result.updatedSectionMap["u1"], "hidden")
        // The rebuilt sequence must NOT contain ahCtrl.
        XCTAssertFalse(result.updatedDesiredFiltered.contains(ahCtrl))
    }

    /// Tiered priority: an unmanaged item to the RIGHT of profile items
    /// still overflows before any profile item, because the tier check
    /// runs before the leftmost-first ordering.
    func testTieredPriorityUnmanagedOverflowsBeforeProfile() {
        // chevron(24) + p1(24) + p2(24) + u1(24) = 96
        // Available 80: profileBaseline = 24 + 24 + 24 = 72 <= 80. Profile fits.
        // Try fitting unmanaged: usedWidth=72 + u1=24 = 96 > 80 — u1 doesn't fit.
        // So u1 overflows, profile stays.
        let desired = makeSequence(
            chevron: chevron,
            visible: ["p1", "p2", "u1"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "p1": 24, "p2": 24, "u1": 24]
        let sectionMap = ["p1": "visible", "p2": "visible", "u1": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: ["u1"],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 80
        )

        XCTAssertEqual(result.overflowUIDs, ["u1"],
                       "u1 should overflow before p1/p2 even though it sits to their right")
    }

    /// Regression lock: at default macOS spacing (16) the planner must
    /// NOT subtract any per-item spacing internally. The May 13 fix
    /// removed double-counted spacing; the planner takes uidWidths
    /// as-is (since macOS bakes spacing into item.bounds.width).
    ///
    /// With chevron(24) + p1(50) + p2(50) = 124 and availableWidth 124,
    /// nothing should overflow. Pre-fix code would have subtracted
    /// (count - 1) * 16 = 32 somewhere, making 124 appear too big
    /// against the budget.
    func testNoDoubleCountedSpacingRegressionLock() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["p1", "p2"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        // Widths already include the macOS-baked spacing.
        let widths: [String: CGFloat] = [chevron: 24, "p1": 50, "p2": 50]
        let sectionMap = ["p1": "visible", "p2": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(
                visible: chevron,
                hidden: hiddenCtrl,
                alwaysHidden: ahCtrl
            ),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 124 // exactly chevron + p1 + p2, no spacing subtraction
        )

        XCTAssertEqual(result.overflowUIDs, [],
                       "no item should overflow when widths sum to exactly the budget — spacing must not be double-counted")
    }
}
