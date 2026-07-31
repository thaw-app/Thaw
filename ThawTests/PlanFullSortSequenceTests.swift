//
//  PlanFullSortSequenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for LayoutSolver.planFullSortSequence.
///
/// Pins down the sequence construction used by applyProfileLayout on
/// notched displays: items grouped AH → hidden → visible, with control
/// items at section boundaries. No-op when current already matches.
@Suite("Plan full sort sequence")
struct PlanFullSortSequenceTests {
    private let hiddenCtrl = "thaw:HiddenControlItem"
    private let ahCtrl = "thaw:AlwaysHiddenControlItem"

    /// Items group by section in the order AH → AH ctrl → hidden → hidden
    /// ctrl → visible. Control items land at the section boundaries.
    @Test("Items group always-hidden, then hidden, then visible")
    func itemsGroupAlwaysHiddenThenHiddenThenVisible() {
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

        #expect(
            sequence == ["ah1", "ah2", ahCtrl, "h1", "h2", hiddenCtrl, "v1", "v2"],
            "sequence must place AH items, then AH ctrl, then hidden items, then hidden ctrl, then visible items"
        )
    }

    /// When the always-hidden control item is absent, the sequence omits
    /// it entirely. AH-tagged items still come before the hidden ctrl.
    @Test("An absent always-hidden control item is omitted from the sequence")
    func emptyAlwaysHiddenControlOmittedFromSequence() {
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

        #expect(sequence == ["h1", hiddenCtrl, "v1"])
        #expect(!sequence.contains(ahCtrl))
    }

    /// An empty desired section is just absent from the sequence; the
    /// section dividers still appear at the correct boundaries.
    @Test("An empty section is omitted while the dividers keep their boundaries")
    func emptySectionIsOmittedFromSequence() {
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
        #expect(sequence == [ahCtrl, hiddenCtrl, "v1"])
    }

    @Test("A single out-of-place item trims the already-ordered prefix")
    func trimsOrderedPrefixForSingleOutOfPlaceItem() {
        let desired = ["v1", "v2", "v3", hiddenCtrl, "h1", "nowPlaying", ahCtrl, "ah1", "ah2"]
        let sectionMap: [String: String] = [
            "v1": "visible", "v2": "visible", "v3": "visible",
            "h1": "hidden", "nowPlaying": "hidden",
            "ah1": "alwaysHidden", "ah2": "alwaysHidden",
        ]
        let currentFlat = ["v1", "v2", "nowPlaying", "v3", hiddenCtrl, "h1", ahCtrl, "ah1", "ah2"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: currentFlat,
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        #expect(sequence == [hiddenCtrl, "v1", "v2", "v3"])
    }

    @Test("A left-edge swap replays from the first out-of-order item")
    func leftEdgeSwapReplaysFromFirstOutOfOrderItem() {
        let desired = ["v1", hiddenCtrl, "h1", ahCtrl, "ah1", "ah2"]
        let sectionMap: [String: String] = [
            "v1": "visible", "h1": "hidden",
            "ah1": "alwaysHidden", "ah2": "alwaysHidden",
        ]
        let currentFlat = ["v1", hiddenCtrl, "h1", ahCtrl, "ah2", "ah1"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: currentFlat,
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        #expect(sequence == ["ah2", ahCtrl, "h1", hiddenCtrl, "v1"])
    }

    @Test("Unmanaged items do not break the prefix trim")
    func unmanagedItemsDoNotBreakPrefixTrim() {
        let desired = ["v1", "v2", hiddenCtrl, "h1"]
        let sectionMap: [String: String] = [
            "v1": "visible", "v2": "visible", "h1": "hidden",
        ]
        let currentFlat = ["v2", "v1", hiddenCtrl, "h1", "unmanaged"]

        let sequence = LayoutSolver.planFullSortSequence(
            currentFlat: currentFlat,
            desiredFiltered: desired,
            sectionMap: sectionMap,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        #expect(sequence == ["v2"])
    }

    /// If currentFlat already filtered against desiredFiltered matches
    /// desiredFiltered exactly, the sequence is empty (no-op signal).
    @Test("A current layout that already matches yields no sequence")
    func noOpWhenAlreadyMatches() {
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

        #expect(sequence == [],
                "no sequence when current already matches desired after filtering")
    }
}
