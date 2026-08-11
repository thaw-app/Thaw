//
//  PlanNotchOverflowTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

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
@Suite("Plan notch overflow")
struct PlanNotchOverflowTests {
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

    /// When the profile fits and there are no unmanaged items, overflow
    /// is empty and inputs pass through unchanged.
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

    /// Profile fits, unmanaged also fits — no overflow.
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

    /// Profile fits, but unmanaged doesn't — overflow only unmanaged,
    /// leftmost-first (chevron-side first).
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

    /// Profile baseline exceeds the budget: all unmanaged overflow,
    /// then profile leftmost overflows until the remainder fits.
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

    /// When chevron width alone equals the budget, all other items
    /// overflow (regardless of tier).
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

    /// When the always-hidden control item is absent, overflowed items
    /// append into the hidden section only — no AH section to consider.
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
        // The rebuilt sequence must NOT contain ahCtrl.
        #expect(!result.updatedDesiredFiltered.contains(ahCtrl))
    }

    /// Tiered priority: an unmanaged item to the RIGHT of profile items
    /// still overflows before any profile item, because the tier check
    /// runs before the leftmost-first ordering.
    @Test("An unmanaged item overflows before a profile item sitting to its left")
    func tieredPriorityUnmanagedOverflowsBeforeProfile() {
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

        #expect(result.overflowUIDs == ["u1"],
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

    /// A negative availableWidth means the budget was computed from invalid,
    /// not-yet-settled geometry: during a display reconnect Control Center
    /// reported a stale off-screen left edge, so rightBoundary went negative
    /// and availableWidth came out at -1202 in the field log. The planner must
    /// not eject items on a budget it cannot trust. Without the guard the
    /// "profile alone exceeds budget" branch ejects every visible item, which
    /// is the exact corruption observed (availableWidth=-1202 -> 13 items
    /// ejected from visible, collapsing the hidden section into visible).
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

    /// A zero budget is equally untrustworthy (Control Center left edge at or
    /// inside the notch boundary) and must not trigger overflow.
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

    /// A non-finite budget (degenerate screen frame / missing geometry) must
    /// not eject either.
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

    /// Guard rail: a small but POSITIVE budget still overflows legitimately, so
    /// the invalid-budget guard does not suppress real overflow on a genuinely
    /// full bar.
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

    /// The visible control item is never ejected, but it must also keep its
    /// saved position when an overflow rebuild runs. The field layout puts the
    /// Thaw icon near the end of the visible section (items after it), not at
    /// the front. Here the chevron sits mid-section; when a profile item
    /// overflows, the chevron must stay between its neighbours rather than jump
    /// to index 0. Red before the fix, which prepended the chevron.
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

    /// A notched display that is the main menu bar display runs overflow —
    /// e.g. a MacBook used on its own, or with the built-in set as main.
    @Test("Overflow runs on a notched main display")
    func overflowRunsOnNotchedMainDisplay() {
        #expect(LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: true,
            activeHasNotch: true,
            activeIsMainDisplay: true
        ))
    }

    /// A notched *secondary* display must NOT run overflow. This is the field
    /// bug: a MacBook built-in next to a non-notched external main display.
    /// The active menu bar transiently flips to the built-in, the 447pt
    /// beside-notch budget ejects two profile items, and they stay stranded in
    /// hidden once focus returns to the external. Gating on the main display
    /// keeps the saved layout intact.
    @Test("Overflow is skipped on a notched secondary display")
    func overflowSkippedOnNotchedSecondaryDisplay() {
        #expect(!LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: true,
            activeHasNotch: true,
            activeIsMainDisplay: false
        ))
    }

    /// A non-notched main display (e.g. an external as the only/primary screen)
    /// has no notch to overflow around.
    @Test("Overflow is skipped on a non-notched main display")
    func overflowSkippedOnNonNotchedMainDisplay() {
        #expect(!LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: true,
            activeHasNotch: false,
            activeIsMainDisplay: true
        ))
    }

    /// While the active menu bar display is unknown (e.g. mid
    /// display-reconfiguration), overflow must not run against a guessed
    /// screen — even one that would qualify (notched + main).
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

    /// MenuBarItemManager.enforceControlItemOrder exists because control items
    /// can transiently appear out of order. If the always-hidden control sits
    /// BEFORE the hidden control in desiredFiltered, hiddenEnd < hiddenStart and
    /// the rebuild slice would trap. The planner must bail with inputs unchanged
    /// instead of crashing.
    @Test("Inverted control-item order yields no overflow instead of trapping")
    func invertedControlOrderYieldsNoOverflowInsteadOfTrapping() {
        // ahCtrl appears before hiddenCtrl — inverted from the expected order.
        let desired = [chevron, "a", "b", ahCtrl, hiddenCtrl]
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24 // only chevron fits — overflow would otherwise be computed
        )

        #expect(result.overflowUIDs == [], "must not eject items when control order is inverted")
        #expect(result.updatedDesiredFiltered == desired)
        #expect(result.updatedSectionMap == sectionMap)
    }

    /// The hidden control can be missing entirely (e.g. during a display
    /// reconnect) while the always-hidden control is still present. That makes
    /// hiddenStart fall back to endIndex, which can land after hiddenEnd — the
    /// same trap shape as inverted order. Must bail, not crash.
    @Test("A missing hidden control with the always-hidden control present yields no overflow")
    func hiddenControlAbsentAlwaysHiddenPresentYieldsNoOverflow() {
        // hiddenCtrl is absent from desiredFiltered entirely.
        let desired = [chevron, "a", "b", ahCtrl]
        let widths: [String: CGFloat] = [chevron: 24, "a": 24, "b": 24]
        let sectionMap = ["a": "visible", "b": "visible"]

        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desired,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: chevron, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: sectionMap,
            uidWidths: widths,
            availableWidth: 24 // only chevron fits — overflow would otherwise be computed
        )

        #expect(result.overflowUIDs == [], "must not eject items when the hidden control is missing")
        #expect(result.updatedDesiredFiltered == desired)
        #expect(result.updatedSectionMap == sectionMap)
    }

    /// Guard rail on the guard itself: when hiddenCtrl and ahCtrl are adjacent
    /// and in the correct order, hiddenStart == hiddenEnd (an empty, but valid,
    /// hidden section). An over-eager `<` instead of `<=` would silently disable
    /// overflow for every user with an empty hidden section, so this must still
    /// compute overflow normally.
    @Test("An empty but correctly ordered hidden section still overflows normally")
    func emptyHiddenSectionInCorrectOrderStillOverflowsNormally() {
        // Same shape as testProfileFitsUnmanagedOverflowsLeftmostFirst: hiddenCtrl
        // and ahCtrl are adjacent (no items between them) via the default empty
        // hidden/alwaysHidden lists in makeSequence.
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

    /// Both control items can be absent from desiredFiltered at once. hiddenStart
    /// and hiddenEnd both fall back to endIndex (trivially equal), so the guard
    /// must not trap — the rebuild proceeds normally and (re)inserts the control
    /// items, since the rebuild always stamps them in regardless of whether they
    /// were present in the input.
    ///
    /// Deliberately NOT asserting "inputs returned unchanged" here: with both
    /// controls absent, hiddenStart == hiddenEnd == endIndex, so the `<=` guard
    /// passes and the function proceeds to a normal rebuild rather than taking
    /// the early-return path. Asserting the actual rebuilt output is correct;
    /// do not "fix" this back to an unchanged-inputs assertion.
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
            availableWidth: 24 // only chevron fits — forces the profile-exceeds-budget branch
        )

        #expect(Set(result.overflowUIDs) == Set(["a", "b"]), "overflow still computed when both controls are absent")
        #expect(
            result.updatedDesiredFiltered == [chevron, hiddenCtrl, "a", "b", ahCtrl],
            "rebuild must not trap and control items are reinserted even though absent from input"
        )
    }

    // MARK: - Tiering does not decide whether anything overflows (#881)

    /// `rebalanceNotchOverflowIfNeeded` calls this planner with every visible
    /// item marked unmanaged, then reads only whether the result is empty in
    /// order to decide whether to hand off to a profile apply. That reading is
    /// only sound if the unmanaged/profile split changes *which* items are
    /// chosen and not *whether* any are — the tiers are a priority order over
    /// one budget, not two budgets.
    ///
    /// Pinned because the gate is what stops #881's storm: the pass used to
    /// hand off before computing a budget at all, re-arming a full apply on
    /// every cache tick for a bar that never overflowed.
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

    /// The other direction: a row over budget is seen as over budget whichever
    /// tier its items are in, so the gate cannot swallow a real ejection.
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
