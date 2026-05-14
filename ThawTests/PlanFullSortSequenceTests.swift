//
//  PlanFullSortSequenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.planFullSortSequence.
///
/// Pins down the sequence construction used by applyProfileLayout on
/// notched displays: items grouped AH → hidden → visible, with control
/// items at section boundaries. No-op when current already matches.
final class PlanFullSortSequenceTests: XCTestCase {
    private let hiddenCtrl = "thaw:HiddenControlItem"
    private let ahCtrl = "thaw:AlwaysHiddenControlItem"

    /// Items group by section in the order AH → AH ctrl → hidden → hidden
    /// ctrl → visible. Control items land at the section boundaries.
    func testItemsGroupAlwaysHiddenThenHiddenThenVisible() {
        // desiredFiltered with controls and items mixed: the planner
        // re-orders into the canonical sequence.
        let desired = ["v1", "v2", hiddenCtrl, "h1", "h2", ahCtrl, "ah1", "ah2"]
        let sectionMap: [String: String] = [
            "v1": "visible", "v2": "visible",
            "h1": "hidden", "h2": "hidden",
            "ah1": "alwaysHidden", "ah2": "alwaysHidden",
        ]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: [], // not matching → must sort
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        XCTAssertEqual(
            sequence,
            ["ah1", "ah2", ahCtrl, "h1", "h2", hiddenCtrl, "v1", "v2"],
            "sequence must place AH items, then AH ctrl, then hidden items, then hidden ctrl, then visible items"
        )
    }

    /// When the always-hidden control item is absent, the sequence omits
    /// it entirely. AH-tagged items still come before the hidden ctrl.
    func testEmptyAlwaysHiddenControlOmittedFromSequence() {
        let desired = ["v1", hiddenCtrl, "h1"]
        let sectionMap: [String: String] = [
            "v1": "visible",
            "h1": "hidden",
        ]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: [],
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        XCTAssertEqual(sequence, ["h1", hiddenCtrl, "v1"])
        XCTAssertFalse(sequence.contains(ahCtrl))
    }

    /// An empty desired section is just absent from the sequence; the
    /// section dividers still appear at the correct boundaries.
    func testEmptySectionIsOmittedFromSequence() {
        // No always-hidden items, no hidden items, just one visible item.
        let desired = ["v1", hiddenCtrl, ahCtrl]
        let sectionMap: [String: String] = ["v1": "visible"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: [],
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        // Empty AH section, empty hidden section, one visible item.
        // Sequence: AH ctrl, hidden ctrl, v1.
        XCTAssertEqual(sequence, [ahCtrl, hiddenCtrl, "v1"])
    }

    /// If currentFlat already filtered against desiredFiltered matches
    /// desiredFiltered exactly, the sequence is empty (no-op signal).
    func testNoOpWhenAlreadyMatches() {
        let desired = ["v1", hiddenCtrl, "h1", ahCtrl, "ah1"]
        let sectionMap: [String: String] = [
            "v1": "visible",
            "h1": "hidden",
            "ah1": "alwaysHidden",
        ]

        // currentFlat contains the same items in the same relative order
        // (plus possibly extras the filter will drop). Filtered to the
        // desired set, it matches desired.
        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: ["unrelated_left", "v1", hiddenCtrl, "h1", ahCtrl, "ah1", "unrelated_right"],
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        XCTAssertEqual(sequence, [],
                       "no sequence when current already matches desired after filtering")
    }
}
