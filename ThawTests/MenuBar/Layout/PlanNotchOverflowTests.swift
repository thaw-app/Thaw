//
//  PlanNotchOverflowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// LayoutSolver.planNotchOverflow: unmanaged items overflow before profile
/// items, leftmost first within a tier, with no double-counted spacing and no
/// per-item subtraction. Pure arithmetic over its inputs.
@Suite("Plan notch overflow")
struct PlanNotchOverflowTests {
    // MARK: - Helpers

    /// chevron, visible profile items, unmanaged, hiddenCtrl, hidden items, ahCtrl, AH items.
    private func makeSequence(
        chevron: String?,
        visible: [String],
        hiddenCtrl: String,
        hidden: [String] = [],
        ahCtrl: String?,
        alwaysHidden: [String] = []
    ) -> [String] {
        var result = [String]()
        if let chevron {
            result.append(chevron)
        }
        result.append(contentsOf: visible)
        result.append(hiddenCtrl)
        result.append(contentsOf: hidden)
        if let ahCtrl {
            result.append(ahCtrl)
        }
        result.append(contentsOf: alwaysHidden)
        return result
    }

    private let chevron = "thaw:VisibleControlItem"
    private let hiddenCtrl = "thaw:HiddenControlItem"
    private let ahCtrl = "thaw:AlwaysHiddenControlItem"

    // MARK: - Scenarios

    @Test("A fitting profile with no unmanaged items overflows nothing")
    func profileFitsNoUnmanagedNoOverflow() {
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

        #expect(result.overflowUIDs == [])
        #expect(result.updatedDesiredFiltered == desired)
        #expect(result.updatedSectionMap == sectionMap)
    }

    @Test("Nothing overflows when the profile and the unmanaged items both fit")
    func profileFitsUnmanagedFitsNoOverflow() {
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

        #expect(result.overflowUIDs == [])
    }

    @Test("Unmanaged items overflow leftmost-first when the profile fits")
    func profileFitsUnmanagedOverflowsLeftmostFirst() {
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

        #expect(result.overflowUIDs == ["u1"])
        #expect(result.updatedSectionMap["u1"] == "hidden")
        #expect(result.updatedSectionMap["u2"] == "visible")
        #expect(result.updatedSectionMap["a"] == "visible")
    }

    @Test("A profile over budget overflows every unmanaged item, then the leftmost profile items")
    func profileBaselineExceedsBudgetOverflowsAllUnmanagedThenLeftmostProfile() {
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

        #expect(Set(result.overflowUIDs) == Set(["u1", "p1", "p2"]))
        #expect(result.updatedSectionMap["u1"] == "hidden")
        #expect(result.updatedSectionMap["p1"] == "hidden")
        #expect(result.updatedSectionMap["p2"] == "hidden")
        #expect(result.updatedSectionMap["p3"] == "visible")
    }

    @Test("Everything overflows when the chevron alone equals the budget")
    func chevronEqualsBudgetEverythingOverflows() {
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

        #expect(Set(result.overflowUIDs) == Set(["p1", "u1"]))
    }

    @Test("Overflow lands in the hidden section when the always-hidden control is absent")
    func alwaysHiddenAbsentOverflowGoesToHidden() {
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

        #expect(result.overflowUIDs == ["u1"])
        #expect(result.updatedSectionMap["u1"] == "hidden")
        #expect(!result.updatedDesiredFiltered.contains(ahCtrl))
    }

    /// The tier check runs before leftmost-first ordering.
    @Test("An unmanaged item overflows before a profile item sitting to its left")
    func tieredPriorityUnmanagedOverflowsBeforeProfile() {
        // chevron(24) + p1(24) + p2(24) + u1(24) = 96
        // Available 80: profileBaseline = 24 + 24 + 24 = 72 <= 80. Profile fits.
        // Try fitting unmanaged: usedWidth=72 + u1=24 = 96 > 80, so u1 doesn't fit.
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

        #expect(result.overflowUIDs == ["u1"],
                "u1 should overflow before p1/p2 even though it sits to their right")
    }

    /// macOS bakes spacing into item widths, so the planner must not subtract
    /// per-item spacing. Old code subtracted (count - 1) * 16, making 124 overflow a 124 budget.
    @Test("Per-item spacing is not double-counted against the budget")
    func noDoubleCountedSpacingRegressionLock() {
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

        #expect(result.overflowUIDs == [],
                "no item should overflow when widths sum to exactly the budget — spacing must not be double-counted")
    }

    // MARK: - Invalid / unsettled geometry guard (issue #666, display reconnect)

    /// A negative budget comes from unsettled geometry: on a display reconnect
    /// Control Center reported a stale left edge and availableWidth was -1202.
    /// Without the guard every visible item was ejected (13 in the field log).
    @Test("A negative budget yields no overflow")
    func negativeAvailableWidthYieldsNoOverflow() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b", "c", "d"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "c": 24, "d": 24]
        let sectionMap = ["a": "visible", "b": "visible", "c": "visible", "d": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: -1202 // exact value from the field log (display reconnect)
        )

        #expect(result.overflowUIDs == [], "must not eject items on a negative (invalid) budget")
        #expect(result.updatedDesiredFiltered == desired)
        #expect(result.updatedSectionMap == sectionMap)
    }

    /// A zero budget (Control Center edge at or inside the notch) is just as untrustworthy.
    @Test("A zero budget yields no overflow")
    func zeroAvailableWidthYieldsNoOverflow() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 0
        )

        #expect(result.overflowUIDs == [], "must not eject items on a zero budget")
    }

    /// A non-finite budget (degenerate or missing screen geometry) must not eject either.
    @Test("A non-finite budget yields no overflow")
    func nonFiniteAvailableWidthYieldsNoOverflow() {
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        for badBudget in [CGFloat.infinity, -.infinity, .nan] {
            let result = LayoutSolver.planNotchOverflow(
                desiredFiltered: desired,
                unmanagedUIDs: [],
                controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
                sectionMap: sectionMap,
                uidWidths: widths,
                availableWidth: badBudget
            )
            #expect(result.overflowUIDs == [], "must not eject items on a non-finite budget (\(badBudget))")
        }
    }

    /// The invalid-budget guard must not suppress real overflow on a full bar.
    @Test("A small but positive budget still overflows")
    func smallPositiveBudgetStillOverflows() {
        // chevron(24) + a + b + c + d (24 each) = 120; budget 60 fits chevron + 1.
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b", "c", "d"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "c": 24, "d": 24]
        let sectionMap = ["a": "visible", "b": "visible", "c": "visible", "d": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 60
        )

        #expect(!result.overflowUIDs.isEmpty, "a genuinely full bar (positive budget) must still overflow")
    }

    /// The chevron is never ejected and must keep its saved slot mid-section when
    /// a rebuild runs; the old code moved it to index 0.
    @Test("The chevron keeps its saved position across an overflow rebuild")
    func chevronKeepsSavedPositionAcrossOverflow() {
        // visible order left-to-right: a, b, chevron, c (chevron mid-list).
        let desired = makeSequence(
            chevron: nil,
            visible: ["a", "b", chevron, "c"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "c": 24]
        let sectionMap = ["a": "visible", "b": "visible", "c": "visible"]

        // profileBaseline = chevron + a + b + c = 96 > 80, so one item overflows.
        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 80
        )

        #expect(result.overflowUIDs == ["a"], "leftmost profile item overflows first")
        #expect(
            result.updatedDesiredFiltered == ["b", chevron, "c", hiddenCtrl, "a", ahCtrl],
            "the chevron must stay between b and c, not be relocated to the front"
        )
        #expect(result.updatedSectionMap["a"] == "hidden")
    }

    // MARK: - Display gate (shouldManageNotchOverflow)

    /// Such as a MacBook alone, or with the built-in set as main.
    @Test("Overflow runs on a notched main display")
    func overflowRunsOnNotchedMainDisplay() {
        #expect(LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: true,
            activeHasNotch: true,
            activeIsMainDisplay: true
        ))
    }

    /// A built-in beside a non-notched external main: the active bar briefly flips
    /// to the built-in, its 447pt budget ejects two items, and they stay stranded.
    @Test("Overflow is skipped on a notched secondary display")
    func overflowSkippedOnNotchedSecondaryDisplay() {
        #expect(!LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: true,
            activeHasNotch: true,
            activeIsMainDisplay: false
        ))
    }

    @Test("Overflow is skipped on a non-notched main display")
    func overflowSkippedOnNonNotchedMainDisplay() {
        #expect(!LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: true,
            activeHasNotch: false,
            activeIsMainDisplay: true
        ))
    }

    /// Mid-reconfiguration, overflow must not run against a guessed screen, even a qualifying one.
    @Test("Overflow is skipped while the active display is unknown")
    func overflowSkippedWhileActiveDisplayUnknown() {
        #expect(!LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: false,
            activeHasNotch: true,
            activeIsMainDisplay: true
        ))
    }

    /// The user toggle wins regardless of geometry.
    @Test("Overflow is skipped when the user toggle is off")
    func overflowSkippedWhenDisabled() {
        #expect(!LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: false,
            activeScreenKnown: true,
            activeHasNotch: true,
            activeIsMainDisplay: true
        ))
    }

    // MARK: - Inverted / missing control-item order guard (Plan 004)

    /// Control items can appear out of order. With ahCtrl before hiddenCtrl,
    /// hiddenEnd < hiddenStart and the rebuild slice would trap.
    @Test("Inverted control-item order yields no overflow instead of trapping")
    func invertedControlOrderYieldsNoOverflowInsteadOfTrapping() {
        // ahCtrl before hiddenCtrl.
        let desired = [chevron, "a", "b", ahCtrl, hiddenCtrl]
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24 // only chevron fits, so overflow would otherwise be computed
        )

        #expect(result.overflowUIDs == [], "must not eject items when control order is inverted")
        #expect(result.updatedDesiredFiltered == desired)
        #expect(result.updatedSectionMap == sectionMap)
    }

    /// A missing hiddenCtrl (during a display reconnect) makes hiddenStart fall back
    /// to endIndex, past hiddenEnd: the same trap shape.
    @Test("A missing hidden control with the always-hidden control present yields no overflow")
    func hiddenControlAbsentAlwaysHiddenPresentYieldsNoOverflow() {
        let desired = [chevron, "a", "b", ahCtrl]
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24 // only chevron fits, so overflow would otherwise be computed
        )

        #expect(result.overflowUIDs == [], "must not eject items when the hidden control is missing")
        #expect(result.updatedDesiredFiltered == desired)
        #expect(result.updatedSectionMap == sectionMap)
    }

    /// Adjacent, ordered controls give hiddenStart == hiddenEnd. A `<` instead of
    /// `<=` would disable overflow for every empty hidden section.
    @Test("An empty but correctly ordered hidden section still overflows normally")
    func emptyHiddenSectionInCorrectOrderStillOverflowsNormally() {
        // makeSequence's empty hidden and always-hidden lists put the controls adjacent.
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
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 90
        )

        #expect(result.overflowUIDs == ["u1"], "empty-but-correctly-ordered hidden section must not suppress overflow")
        #expect(
            result.updatedDesiredFiltered == [chevron, "a", "u2", hiddenCtrl, "u1", ahCtrl],
            "overflowed item must land between hiddenCtrl and ahCtrl"
        )
    }

    /// With both controls absent, hiddenStart == hiddenEnd == endIndex, so the
    /// guard passes and the rebuild re-inserts the controls. Asserting unchanged
    /// inputs here would be wrong; do not "fix" it.
    @Test("Both controls absent rebuilds without trapping")
    func bothControlsAbsentYieldsNoTrap() {
        let desired = [chevron, "a", "b"]
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24 // only chevron fits, forcing the profile-exceeds-budget branch
        )

        #expect(Set(result.overflowUIDs) == Set(["a", "b"]), "overflow still computed when both controls are absent")
        #expect(
            result.updatedDesiredFiltered == [chevron, hiddenCtrl, "a", "b", ahCtrl],
            "rebuild must not trap and control items are reinserted even though absent from input"
        )
    }

    // MARK: - Tiering does not decide whether anything overflows (#881)

    /// `rebalanceNotchOverflowIfNeeded` marks every item unmanaged and only checks
    /// for an empty result, which is sound only if tiers change which items
    /// overflow, not whether any do. This gate stopped #881's apply-every-tick storm.
    @Test("A row that fits overflows nothing under either tiering")
    func fittingRowOverflowsNothingRegardlessOfTiering() {
        // chevron(24) + a(24) + b(24) + c(24) = 96
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b", "c"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "c": 24]
        let sectionMap = ["a": "visible", "b": "visible", "c": "visible"]

        func overflow(unmanagedUIDs: [String]) -> [String] {
            LayoutSolver.planNotchOverflow(
                desiredFiltered: desired,
                unmanagedUIDs: unmanagedUIDs,
                controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
                sectionMap: sectionMap,
                uidWidths: widths,
                availableWidth: 100 // fits 96
            ).overflowUIDs
        }

        #expect(overflow(unmanagedUIDs: []) == [], "all profile items")
        #expect(overflow(unmanagedUIDs: ["a", "b", "c"]) == [], "all unmanaged, as the rebalance pass calls it")
        #expect(overflow(unmanagedUIDs: ["b"]) == [], "mixed")
    }

    /// A real ejection is seen whichever tier its items are in.
    @Test("A row over budget overflows something under either tiering")
    func overflowingRowIsSeenRegardlessOfTiering() {
        // chevron(24) + a(24) + b(24) + c(24) = 96, budget 70
        let desired = makeSequence(
            chevron: chevron,
            visible: ["a", "b", "c"],
            hiddenCtrl: hiddenCtrl,
            ahCtrl: ahCtrl
        )
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24, "c": 24]
        let sectionMap = ["a": "visible", "b": "visible", "c": "visible"]

        func overflow(unmanagedUIDs: [String]) -> [String] {
            LayoutSolver.planNotchOverflow(
                desiredFiltered: desired,
                unmanagedUIDs: unmanagedUIDs,
                controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
                sectionMap: sectionMap,
                uidWidths: widths,
                availableWidth: 70
            ).overflowUIDs
        }

        #expect(!overflow(unmanagedUIDs: []).isEmpty, "all profile items")
        #expect(!overflow(unmanagedUIDs: ["a", "b", "c"]).isEmpty, "all unmanaged, as the rebalance pass calls it")
        #expect(!overflow(unmanagedUIDs: ["b"]).isEmpty, "mixed")
    }
}
