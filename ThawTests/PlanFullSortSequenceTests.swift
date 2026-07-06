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
        let sectionMap = ["v1": "visible"]

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

    /// A single item sitting in the wrong section replays only from the
    /// first physical divergence, not the whole bar. Field case: Control
    /// Center's transient Now Playing widget reappears in the visible
    /// section while the saved layout wants it hidden; the four
    /// always-hidden-side items that are already in order must not move.
    func testTrimsAlreadyOrderedPrefixForSingleOutOfPlaceItem() {
        // Physical target (left to right):
        //   ah1, ah2, ahCtrl, h1, nowPlaying, hiddenCtrl, v1, v2, v3
        let desired = ["v1", "v2", "v3", hiddenCtrl, "h1", "nowPlaying", ahCtrl, "ah1", "ah2"]
        let sectionMap: [String: String] = [
            "v1": "visible", "v2": "visible", "v3": "visible",
            "h1": "hidden", "nowPlaying": "hidden",
            "ah1": "alwaysHidden", "ah2": "alwaysHidden",
        ]
        // Current physical order: nowPlaying sits in the visible section
        // (between v2 and v3); everything else already matches. currentFlat
        // is flattened visible-first with left-to-right section blocks.
        let currentFlat = ["v1", "v2", "nowPlaying", "v3", hiddenCtrl, "h1", ahCtrl, "ah1", "ah2"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: currentFlat,
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        // Physical prefix ah1, ah2, ahCtrl, h1 is already in order, and
        // nowPlaying's current position (in visible) is still to the right
        // of h1, so the replay starts at the first item that must cross it:
        // the hidden control divider.
        XCTAssertEqual(sequence, [hiddenCtrl, "v1", "v2", "v3"])
    }

    /// A swap at the far left keeps the item that still forms an ordered
    /// prefix (ah1) and replays everything that must land to its right.
    func testLeftEdgeSwapReplaysFromFirstOutOfOrderItem() {
        let desired = ["v1", hiddenCtrl, "h1", ahCtrl, "ah1", "ah2"]
        let sectionMap: [String: String] = [
            "v1": "visible",
            "h1": "hidden",
            "ah1": "alwaysHidden", "ah2": "alwaysHidden",
        ]
        // ah2 and ah1 are swapped at the leftmost positions.
        let currentFlat = ["v1", hiddenCtrl, "h1", ahCtrl, "ah2", "ah1"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: currentFlat,
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        // ah1 (physical position 1) is an ordered prefix on its own; ah2
        // (position 0) breaks the increasing order, so the replay starts
        // there. Replaying [ah2, ahCtrl, h1, hiddenCtrl, v1] to the right
        // of the unmoved ah1 yields the target order.
        XCTAssertEqual(sequence, ["ah2", ahCtrl, "h1", hiddenCtrl, "v1"])
    }

    /// Unmanaged items interleaved with the untouched prefix don't affect
    /// the trim; they're never moved on either path.
    func testUnmanagedItemsDoNotBreakPrefixTrim() {
        let desired = ["v1", "v2", hiddenCtrl, "h1"]
        let sectionMap: [String: String] = [
            "v1": "visible", "v2": "visible",
            "h1": "hidden",
        ]
        // "unmanaged" is not part of the desired sequence and sits next to
        // h1 in the hidden section; v2 and v1 are swapped in the visible
        // section. h1, hiddenCtrl, and v1 form an ordered physical prefix,
        // so only v2 replays: extracted from its position left of v1 and
        // re-appended at the far right.
        let currentFlat = ["v2", "v1", hiddenCtrl, "h1", "unmanaged"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: currentFlat,
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        XCTAssertEqual(sequence, ["v2"])
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
