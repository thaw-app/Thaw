//
//  DesiredSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
import ThawLayout

/// Characterization for LayoutSolver.DesiredSectionOrder and
/// LayoutSolver.splitDesiredFiltered(_:controlUIDs:), the deterministic
/// bridge from the flat composer output to the per-section arrays the
/// weight-model runtime consumes.
@Suite("DesiredSectionOrder split")
struct DesiredSectionOrderTests {
    private static let visible = "thaw:visible"
    private static let hidden = "thaw:hidden"
    private static let alwaysHidden = "thaw:alwaysHidden"

    private static var controlUIDs: ControlUIDs {
        ControlUIDs(visible: visible, hidden: hidden, alwaysHidden: alwaysHidden)
    }

    // MARK: - Round trip with flattenCurrentSections

    @Test("split is the inverse of flatten for a full three-section layout")
    func splitInvertsFlatten() {
        let visibleItems = [Self.visible, "com.a:one", "com.b:two"]
        let hiddenItems = ["com.c:three", "com.d:four"]
        let alwaysHiddenItems = ["com.e:five"]

        let flat = LayoutSolver.flattenCurrentSections(
            visible: visibleItems,
            hidden: hiddenItems,
            alwaysHidden: alwaysHiddenItems,
            hiddenCtrlUID: Self.hidden,
            ahCtrlUID: Self.alwaysHidden
        )

        let split = LayoutSolver.splitDesiredFiltered(flat, controlUIDs: Self.controlUIDs)

        // The visible array keeps the chevron control item, matching
        // flattenCurrentSections' contract and RuntimeSectionController's
        // rule that the movable visible control stays part of visible order.
        // The hidden and always-hidden control items are delimiters, so
        // they are dropped from the per-section arrays.
        #expect(split.visible == visibleItems)
        #expect(split.hidden == hiddenItems)
        #expect(split.alwaysHidden == alwaysHiddenItems)
    }

    @Test("split is the inverse of flatten when always-hidden is disabled")
    func splitInvertsFlattenWithoutAlwaysHidden() {
        let visibleItems = [Self.visible, "com.a:one"]
        let hiddenItems = ["com.c:three"]

        let flat = LayoutSolver.flattenCurrentSections(
            visible: visibleItems,
            hidden: hiddenItems,
            alwaysHidden: [],
            hiddenCtrlUID: Self.hidden,
            ahCtrlUID: nil
        )

        let controlUIDs = ControlUIDs(
            visible: Self.visible,
            hidden: Self.hidden,
            alwaysHidden: nil
        )
        let split = LayoutSolver.splitDesiredFiltered(flat, controlUIDs: controlUIDs)

        #expect(split.visible == visibleItems)
        #expect(split.hidden == hiddenItems)
        #expect(split.alwaysHidden == [])
    }

    // MARK: - Bracketing

    @Test("an item after the hidden control but with no always-hidden control lands in hidden")
    func hiddenSectionWithoutAlwaysHiddenDelimiter() {
        let flat = [Self.visible, "com.a:one", Self.hidden, "com.c:three", "com.d:four"]
        let controlUIDs = ControlUIDs(
            visible: Self.visible,
            hidden: Self.hidden,
            alwaysHidden: nil
        )

        let split = LayoutSolver.splitDesiredFiltered(flat, controlUIDs: controlUIDs)

        #expect(split.visible == [Self.visible, "com.a:one"])
        #expect(split.hidden == ["com.c:three", "com.d:four"])
        #expect(split.alwaysHidden == [])
    }

    @Test("empty sections survive the split")
    func emptySections() {
        // Only control items: every section is empty.
        let flat = [Self.visible, Self.hidden, Self.alwaysHidden]
        let split = LayoutSolver.splitDesiredFiltered(flat, controlUIDs: Self.controlUIDs)

        #expect(split.visible == [Self.visible])
        #expect(split.hidden == [])
        #expect(split.alwaysHidden == [])
    }

    @Test("a flat sequence with no hidden control item is entirely visible")
    func noHiddenControlItem() {
        let flat = [Self.visible, "com.a:one", "com.b:two"]
        let split = LayoutSolver.splitDesiredFiltered(flat, controlUIDs: Self.controlUIDs)

        #expect(split.visible == [Self.visible, "com.a:one", "com.b:two"])
        #expect(split.hidden == [])
        #expect(split.alwaysHidden == [])
    }

    // MARK: - Determinism / source of truth

    @Test("physical bracketing wins over a contradictory section map")
    func bracketingIsTheSourceOfTruth() {
        // 'com.c:three' sits physically in the hidden bracket but a stale
        // sectionMap claims it is visible. splitDesiredFiltered deliberately
        // does not consult sectionMap; the bracketing is the truth the
        // weight model will realize.
        let flat = [Self.visible, "com.a:one", Self.hidden, "com.c:three", Self.alwaysHidden]

        let split = LayoutSolver.splitDesiredFiltered(flat, controlUIDs: Self.controlUIDs)

        #expect(split.hidden == ["com.c:three"])
        #expect(!split.visible.contains("com.c:three"))
    }

    // MARK: - Subscript and persisted shape

    @Test("subscript reads and writes each section by name")
    func subscriptAccess() {
        var order = LayoutSolver.DesiredSectionOrder()
        order[.visible] = [Self.visible, "com.a:one"]
        order[.hidden] = ["com.c:three"]
        order[.alwaysHidden] = ["com.e:five"]

        #expect(order[.visible] == [Self.visible, "com.a:one"])
        #expect(order[.hidden] == ["com.c:three"])
        #expect(order[.alwaysHidden] == ["com.e:five"])
    }

    @Test("asPersistedDict round-trips through the string-keyed planner input shape")
    func asPersistedDictShape() {
        let order = LayoutSolver.DesiredSectionOrder(
            visible: [Self.visible, "com.a:one"],
            hidden: ["com.c:three"],
            alwaysHidden: ["com.e:five"]
        )

        let dict = order.asPersistedDict
        #expect(dict["visible"] == [Self.visible, "com.a:one"])
        #expect(dict["hidden"] == ["com.c:three"])
        #expect(dict["alwaysHidden"] == ["com.e:five"])
    }
}
