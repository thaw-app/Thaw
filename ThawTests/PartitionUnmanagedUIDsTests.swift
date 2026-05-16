//
//  PartitionUnmanagedUIDsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.partitionUnmanagedUIDs, the
/// pure filter Phase 3 of applyProfileLayout uses to decide which UIDs
/// flow into planUnmanagedPlacement.
///
/// Pins down two invariants the field-reported "Thaw icon keeps moving"
/// regression turned out to depend on:
///
/// 1. All three Thaw control items (hidden, alwaysHidden, visible) are
///    excluded from the result. saveSectionOrder omits control items
///    from savedSectionOrder by design, so they would never appear in
///    desiredUIDs and would otherwise leak into planUnmanagedPlacement,
///    which routes them through NewItemsPlacement and causes the LCS
///    planner to emit spurious control-item moves every cycle.
/// 2. Input order is preserved. Downstream consumers (LCS planner) use
///    the filtered sequence as iteration order for placement
///    application, so reordering here would silently change placement
///    outcomes.
final class PartitionUnmanagedUIDsTests: XCTestCase {
    /// All three control items are present in current and excluded by
    /// the filter, even when none of them appear in desiredUIDs. This
    /// is the case the original bug missed (visibleCtrlUID exclusion
    /// was absent from the inline filter).
    func testAllThreeControlItemsExcluded() {
        let hidden = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"
        let ah = "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden"
        let visible = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
        let app = "com.example.app:Item-0"
        let currentFlat = [hidden, visible, app, ah]

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: [],
            hiddenCtrlUID: hidden,
            ahCtrlUID: ah,
            visibleCtrlUID: visible
        )

        XCTAssertEqual(result, [app])
    }

    /// `nil` control UIDs are tolerated (the alwaysHidden control item
    /// is absent on configurations where the user disabled that
    /// section). Other exclusions still apply.
    func testNilControlUIDsToleratedAndOtherExclusionsHold() {
        let hidden = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"
        let visible = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
        let saved = "com.example.saved:Item-0"
        let unsaved = "com.example.fresh:Item-0"
        let currentFlat = [hidden, saved, visible, unsaved]

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: [saved],
            hiddenCtrlUID: hidden,
            ahCtrlUID: nil,
            visibleCtrlUID: visible
        )

        XCTAssertEqual(result, [unsaved])
    }

    /// Items present in desiredUIDs (i.e., already covered by
    /// savedSectionOrder or the profile spec) are excluded. Only items
    /// the desired sequence doesn't know about should reach
    /// planUnmanagedPlacement.
    func testItemsInDesiredUIDsAreExcluded() {
        let saved = "com.example.saved:Item-0"
        let unsaved = "com.example.fresh:Item-0"

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [saved, unsaved],
            desiredUIDs: [saved],
            hiddenCtrlUID: nil,
            ahCtrlUID: nil,
            visibleCtrlUID: nil
        )

        XCTAssertEqual(result, [unsaved])
    }

    /// Input order is preserved. The LCS planner iterates the result in
    /// order to decide insertion positions, so reordering here would
    /// silently change placement outcomes for the user.
    func testInputOrderIsPreserved() {
        let a = "com.example.a:Item-0"
        let b = "com.example.b:Item-0"
        let c = "com.example.c:Item-0"

        // Deliberately not alphabetical.
        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [c, a, b],
            desiredUIDs: [],
            hiddenCtrlUID: nil,
            ahCtrlUID: nil,
            visibleCtrlUID: nil
        )

        XCTAssertEqual(result, [c, a, b])
    }

    /// Empty currentFlat returns an empty result without crashing on
    /// any nil/non-nil control UID combination.
    func testEmptyCurrentFlatReturnsEmpty() {
        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [],
            desiredUIDs: ["com.example.app:Item-0"],
            hiddenCtrlUID: "h",
            ahCtrlUID: "ah",
            visibleCtrlUID: "v"
        )

        XCTAssertTrue(result.isEmpty)
    }
}
