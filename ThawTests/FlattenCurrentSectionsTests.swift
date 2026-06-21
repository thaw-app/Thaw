//
//  FlattenCurrentSectionsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Tests for LayoutSolver.flattenCurrentSections, the pure helper that builds
/// the ordered currentFlat sequence applyProfileLayout and the log-replay
/// harness both consume.
final class FlattenCurrentSectionsTests: XCTestCase {
    private let hiddenCtrl = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"
    private let ahCtrl = "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden"

    /// Items are laid out visible, hidden control, hidden, always-hidden
    /// control, always-hidden. The visible control item rides along in the
    /// visible array and is not reinserted.
    func testOrderWithAlwaysHiddenPresent() {
        let visibleCtrl = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
        let result = LayoutSolver.flattenCurrentSections(
            visible: [visibleCtrl, "a:Item-0", "b:Item-0"],
            hidden: ["c:Item-0"],
            alwaysHidden: ["d:Item-0"],
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        XCTAssertEqual(
            result,
            [visibleCtrl, "a:Item-0", "b:Item-0", hiddenCtrl, "c:Item-0", ahCtrl, "d:Item-0"]
        )
    }

    /// With no always-hidden control item, its boundary marker is omitted but
    /// any always-hidden items still follow the hidden section.
    func testAlwaysHiddenControlOmittedWhenNil() {
        let result = LayoutSolver.flattenCurrentSections(
            visible: ["a:Item-0"],
            hidden: ["b:Item-0"],
            alwaysHidden: ["c:Item-0"],
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        XCTAssertEqual(result, ["a:Item-0", hiddenCtrl, "b:Item-0", "c:Item-0"])
    }

    /// Empty sections still emit the hidden control item, which marks the
    /// visible/hidden boundary.
    func testEmptySectionsEmitOnlyHiddenControl() {
        let result = LayoutSolver.flattenCurrentSections(
            visible: [],
            hidden: [],
            alwaysHidden: [],
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: nil
        )

        XCTAssertEqual(result, [hiddenCtrl])
    }
}
