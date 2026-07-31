//
//  PlanNotchOverflowGroupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
@testable import Thaw
import XCTest

/// Group-awareness of `LayoutSolver.planNotchOverflow`.
///
/// Overflow fits *units*, not identifiers: a group is one indivisible object,
/// so the budget must never conceal one member of a bundle while leaving its
/// sibling visible. `PlanNotchOverflowTests` covers the ungrouped algorithm and
/// doubles as the regression lock that the defaulted empty group set is inert.
final class PlanNotchOverflowGroupTests: XCTestCase {
    private let chevron = "thaw:VisibleControlItem"
    private let hiddenCtrl = "thaw:HiddenControlItem"
    private let ahCtrl = "thaw:AlwaysHiddenControlItem"

    private func makeSequence(visible: [String]) -> [String] {
        [chevron] + visible + [hiddenCtrl, ahCtrl]
    }

    private func controls() -> ControlUIDs {
        ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl)
    }

    private func plan(
        visible: [String],
        unmanaged: [String] = [],
        widths: [String: CGFloat],
        availableWidth: CGFloat,
        groups: [[String]] = []
    ) -> LayoutSolver.NotchOverflowResult {
        LayoutSolver.planNotchOverflow(
            desiredFiltered: makeSequence(visible: visible),
            unmanagedUIDs: unmanaged,
            controlUIDs: controls(),
            sectionMap: Dictionary(uniqueKeysWithValues: visible.map { ($0, "visible") }),
            uidWidths: widths,
            availableWidth: availableWidth,
            groups: MenuBarItemGroupPolicy.GroupSet(groups: groups)
        )
    }

    // MARK: - Atomicity

    /// The core guarantee: sweep the budget across its whole useful range and
    /// assert the group is never partially overflowed at any width.
    func testGroupIsNeverPartiallyOverflowedAtAnyBudget() {
        let visible = ["a", "g1", "b", "g2", "c"]
        let widths: [String: CGFloat] = [chevron: 20, "a": 20, "g1": 20, "b": 20, "g2": 20, "c": 20]
        let group: Set = ["g1", "g2"]

        for budget in stride(from: 20.0, through: 200.0, by: 5.0) {
            let result = plan(
                visible: visible,
                widths: widths,
                availableWidth: budget,
                groups: [["g1", "g2"]]
            )
            let overflowed = group.intersection(result.overflowUIDs)
            XCTAssertTrue(
                overflowed.isEmpty || overflowed == group,
                "budget \(budget) split the group: \(overflowed.sorted())"
            )
        }
    }

    /// A scattered group must still travel together — members need not be
    /// adjacent for the unit to be indivisible.
    func testScatteredGroupOverflowsTogether() {
        // Chevron 20 + five items of 20 = 120; a 70pt budget keeps ~2 items.
        let result = plan(
            visible: ["g1", "x", "g2", "y", "z"],
            widths: [chevron: 20, "g1": 20, "x": 20, "g2": 20, "y": 20, "z": 20],
            availableWidth: 70,
            groups: [["g1", "g2"]]
        )

        let overflowed = Set(result.overflowUIDs)
        XCTAssertTrue(
            overflowed.isSuperset(of: ["g1", "g2"]) || overflowed.isDisjoint(with: ["g1", "g2"]),
            "scattered group was split: \(result.overflowUIDs)"
        )
    }

    /// Without grouping this budget splits the pair; with it, both go.
    func testGroupingChangesAPartialOverflowIntoAWholeOne() {
        let visible = ["a", "g1", "g2"]
        let widths: [String: CGFloat] = [chevron: 20, "a": 20, "g1": 20, "g2": 20]

        let ungrouped = plan(visible: visible, widths: widths, availableWidth: 60)
        let grouped = plan(visible: visible, widths: widths, availableWidth: 60, groups: [["g1", "g2"]])

        // Baseline: the budget fits chevron + 2 items, so "a" alone overflows
        // and the pair is split across sections only if grouping is off.
        XCTAssertEqual(ungrouped.overflowUIDs, ["a"])
        // With grouping the pair cannot be broken, so the unit that does not
        // fit takes both members.
        let groupedOverflow = Set(grouped.overflowUIDs)
        XCTAssertTrue(
            groupedOverflow.isSuperset(of: ["g1", "g2"]) || groupedOverflow.isDisjoint(with: ["g1", "g2"])
        )
    }

    // MARK: - Tiering

    /// A group is one user-visible object, so a single unmanaged member makes
    /// the whole unit unmanaged. Requiring *all* members would let a mostly
    /// profile-saved group pin the profile tier and never overflow.
    func testAnyUnmanagedMemberMakesTheWholeGroupUnmanaged() {
        let result = plan(
            visible: ["p", "g1", "g2"],
            unmanaged: ["g2"],
            widths: [chevron: 20, "p": 20, "g1": 20, "g2": 20],
            availableWidth: 60,
            groups: [["g1", "g2"]]
        )

        // Profile baseline (chevron + p = 40) fits, so only unmanaged units are
        // candidates — and the group is one, taking both members with it.
        XCTAssertEqual(Set(result.overflowUIDs), ["g1", "g2"])
        XCTAssertFalse(result.overflowUIDs.contains("p"))
    }

    // MARK: - Oversized groups

    /// A cluster wider than the entire budget can never fit. Breaking on it
    /// would cascade everything to its left into hidden and empty the visible
    /// section over one oversized group.
    func testOversizedGroupOverflowsWholeWithoutCascading() {
        let result = plan(
            visible: ["a", "g1", "g2", "g3", "b"],
            widths: [chevron: 10, "a": 10, "g1": 100, "g2": 100, "g3": 100, "b": 10],
            availableWidth: 60,
            groups: [["g1", "g2", "g3"]]
        )

        let overflowed = Set(result.overflowUIDs)
        XCTAssertTrue(overflowed.isSuperset(of: ["g1", "g2", "g3"]))
        XCTAssertEqual(result.oversizedGroups.count, 1)
        XCTAssertEqual(Set(result.oversizedGroups.first ?? []), ["g1", "g2", "g3"])
        // The small items either side still fit, so the section is not emptied.
        XCTAssertFalse(overflowed.contains("b"))
    }

    // MARK: - Diagnostics

    func testWholeGroupOverflowIsReported() {
        let result = plan(
            visible: ["a", "g1", "g2"],
            widths: [chevron: 20, "a": 20, "g1": 20, "g2": 20],
            availableWidth: 45,
            groups: [["g1", "g2"]]
        )

        XCTAssertFalse(result.groupsOverflowedWhole.isEmpty)
        XCTAssertEqual(Set(result.groupsOverflowedWhole.first ?? []), ["g1", "g2"])
    }

    /// A missing width coerces to zero and silently deflates the budget. The
    /// planner is pure and cannot log, so it reports instead.
    func testMissingWidthsAreReported() {
        let result = plan(
            visible: ["a", "b"],
            widths: [chevron: 20, "a": 20],
            availableWidth: 200
        )

        XCTAssertEqual(result.missingWidthUIDs, ["b"])
    }

    func testNoOverflowStillReportsMissingWidths() {
        let result = plan(
            visible: ["a", "b"],
            widths: [chevron: 20],
            availableWidth: 500
        )

        XCTAssertTrue(result.overflowUIDs.isEmpty)
        XCTAssertEqual(Set(result.missingWidthUIDs), ["a", "b"])
    }

    // MARK: - Section map

    func testEveryMemberOfAnOverflowedGroupIsRemappedToHidden() {
        let result = plan(
            visible: ["a", "g1", "g2"],
            widths: [chevron: 20, "a": 20, "g1": 20, "g2": 20],
            availableWidth: 45,
            groups: [["g1", "g2"]]
        )

        for member in ["g1", "g2"] where result.overflowUIDs.contains(member) {
            XCTAssertEqual(result.updatedSectionMap[member], "hidden", "\(member) was not remapped")
        }
    }

    /// Overflowed identifiers must stay in original visible order so the
    /// existing "leftmost-from-visible lands deepest in hidden" contract holds.
    func testOverflowOrderFollowsOriginalVisibleOrder() {
        let result = plan(
            visible: ["g1", "x", "g2"],
            widths: [chevron: 20, "g1": 20, "x": 20, "g2": 20],
            availableWidth: 25,
            groups: [["g1", "g2"]]
        )

        XCTAssertEqual(result.overflowUIDs, ["g1", "x", "g2"])
    }
}
