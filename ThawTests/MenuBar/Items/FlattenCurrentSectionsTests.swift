//
//  FlattenCurrentSectionsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Tests for LayoutSolver.flattenCurrentSections, the pure helper that builds
/// the ordered currentFlat sequence applyProfileLayout and the log-replay
/// harness both consume.
@Suite("Flatten current sections")
struct FlattenCurrentSectionsTests {
    private let hiddenCtrl = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"
    private let ahCtrl = "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden"

    /// Items are laid out visible, hidden control, hidden, always-hidden
    /// control, always-hidden. The visible control item rides along in the
    /// visible array and is not reinserted.
    @Test("Sections flatten in menu bar order when the always-hidden control is present")
    func orderWithAlwaysHiddenPresent() {
        let visibleCtrl = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
        let result = LayoutSolver.flattenCurrentSections(
            visible: [visibleCtrl, "a:Item-0", "b:Item-0"],
            hidden: ["c:Item-0"],
            alwaysHidden: ["d:Item-0"],
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        #expect(
            result ==
                [visibleCtrl, "a:Item-0", "b:Item-0", hiddenCtrl, "c:Item-0", ahCtrl, "d:Item-0"]
        )
    }

    /// With no always-hidden control item, its boundary marker is omitted but
    /// any always-hidden items still follow the hidden section.
    ///
    /// Nothing in the output then distinguishes `c:Item-0` from a hidden item,
    /// which is why `applyProfileLayout` refuses to plan at all when the
    /// always-hidden section is enabled and its divider did not resolve: every
    /// always-hidden item reads as a cross-section mismatch, and the moves that
    /// answer it change nothing, so the next pass plans them again (#881).
    @Test("A nil always-hidden control omits the marker but keeps its items")
    func alwaysHiddenControlOmittedWhenNil() {
        let result = LayoutSolver.flattenCurrentSections(
            visible: ["a:Item-0"],
            hidden: ["b:Item-0"],
            alwaysHidden: ["c:Item-0"],
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        #expect(result == ["a:Item-0", hiddenCtrl, "b:Item-0", "c:Item-0"])
    }

    /// Empty sections still emit the hidden control item, which marks the
    /// visible/hidden boundary.
    @Test("Empty sections still emit the hidden control item")
    func emptySectionsEmitOnlyHiddenControl() {
        let result = LayoutSolver.flattenCurrentSections(
            visible: [],
            hidden: [],
            alwaysHidden: [],
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        #expect(result == [hiddenCtrl])
    }
}
