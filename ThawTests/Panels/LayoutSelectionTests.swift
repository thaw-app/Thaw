//
//  LayoutSelectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

struct LayoutSelectionTests {
    typealias Unit = LayoutSelection.Unit

    /// Visible shows a, b, the group g1+g2, the control item thaw and c, left to right.
    static let visible = [
        Unit(memberIDs: ["a"], isSelectable: true),
        Unit(memberIDs: ["b"], isSelectable: true),
        Unit(memberIDs: ["g1", "g2"], isSelectable: true),
        Unit(memberIDs: ["thaw"], isSelectable: false),
        Unit(memberIDs: ["c"], isSelectable: true),
    ]
    static let hidden = [Unit(memberIDs: ["h1"], isSelectable: true), Unit(memberIDs: ["h2"], isSelectable: true)]

    private func selection(_ clicks: [(String, MenuBarSectionName, LayoutSelection.Click)]) -> LayoutSelection {
        var selection = LayoutSelection()
        for (id, section, kind) in clicks {
            selection.click(id, in: section, units: section == .visible ? Self.visible : Self.hidden, kind: kind)
        }
        return selection
    }

    @Test("Command toggles, Shift extends and a plain click replaces")
    func modifiersPickTheClick() {
        #expect(LayoutSelection.Click(command: true, shift: false) == .toggle)
        #expect(LayoutSelection.Click(command: true, shift: true) == .toggle)
        #expect(LayoutSelection.Click(command: false, shift: true) == .extend)
        #expect(LayoutSelection.Click(command: false, shift: false) == .replace)
    }

    @Test("A plain click selects just the clicked item")
    func plainClickReplaces() {
        let selection = selection([("a", .visible, .toggle), ("h1", .hidden, .toggle), ("b", .visible, .replace)])
        #expect(selection.itemIDs == [.visible: ["b"]])
        #expect(selection.anchor == LayoutSelection.Anchor(section: .visible, itemID: "b"))
        #expect(selection.count == 1)
    }

    @Test("A Command click adds an item, across sections, and a second one removes it")
    func commandClickToggles() {
        var selection = selection([("a", .visible, .toggle), ("h2", .hidden, .toggle)])
        #expect(selection.itemIDs == [.visible: ["a"], .hidden: ["h2"]])
        #expect(selection.sections == [.visible, .hidden])

        selection.click("h2", in: .hidden, units: Self.hidden, kind: .toggle)
        #expect(selection.itemIDs == [.visible: ["a"]])
        #expect(!selection.contains("h2"))
        #expect(selection.contains("a"))
    }

    @Test("Clicking one member of a group selects the whole group")
    func groupsAreOneUnit() {
        var selection = selection([("g2", .visible, .replace)])
        #expect(selection.itemIDs == [.visible: ["g1", "g2"]])
        #expect(selection.count == 2)

        selection.click("g1", in: .visible, units: Self.visible, kind: .toggle)
        #expect(selection.isEmpty)
    }

    @Test("A Shift click selects every selectable unit from the anchor, in either direction")
    func shiftClickExtends() {
        let rightward = selection([("b", .visible, .replace), ("c", .visible, .extend)])
        #expect(rightward.itemIDs == [.visible: ["b", "g1", "g2", "c"]])
        #expect(rightward.anchor?.itemID == "b")

        let leftward = selection([("c", .visible, .replace), ("a", .visible, .extend)])
        #expect(leftward.itemIDs == [.visible: ["a", "b", "g1", "g2", "c"]])
    }

    @Test("A Shift click keeps what Command clicks selected before")
    func shiftClickAddsToTheSelection() {
        let selection = selection([("h1", .hidden, .toggle), ("a", .visible, .toggle), ("b", .visible, .extend)])
        #expect(selection.itemIDs == [.hidden: ["h1"], .visible: ["a", "b"]])
    }

    @Test("A Shift click with no anchor in its section selects just the clicked item")
    func shiftClickWithoutAnchorReplaces() {
        #expect(selection([("b", .visible, .extend)]).itemIDs == [.visible: ["b"]])
        #expect(selection([("h1", .hidden, .replace), ("b", .visible, .extend)]).itemIDs == [.visible: ["b"]])
    }

    @Test("Control items cannot be selected; a plain click on one clears, other clicks do nothing")
    func unselectableItemsStayOut() {
        #expect(selection([("a", .visible, .replace), ("thaw", .visible, .replace)]).isEmpty)
        #expect(selection([("a", .visible, .replace), ("thaw", .visible, .toggle)]).itemIDs == [.visible: ["a"]])
        #expect(selection([("a", .visible, .replace), ("unknown", .visible, .extend)]).itemIDs == [.visible: ["a"]])
    }

    @Test("Clear empties the selection and drops the anchor")
    func clearEmptiesEverything() {
        var selection = selection([("a", .visible, .replace)])
        selection.clear()
        #expect(selection.isEmpty)
        #expect(selection.anchor == nil)
    }

    @Test("Items a section no longer shows, or no longer lets move, are deselected")
    func retainDropsVanishedItems() {
        var selection = selection([("a", .visible, .replace), ("b", .visible, .toggle), ("h1", .hidden, .toggle)])
        selection.retain([Unit(memberIDs: ["a"], isSelectable: false), Unit(memberIDs: ["c"], isSelectable: true)], in: .visible)
        #expect(selection.itemIDs == [.hidden: ["h1"]])

        selection.retain([], in: .hidden)
        #expect(selection.isEmpty)
    }

    @Test("The anchor goes once its item is gone, and stays while it is shown")
    func retainKeepsALiveAnchor() {
        var selection = selection([("a", .visible, .replace)])
        selection.retain(Self.visible, in: .visible)
        #expect(selection.anchor?.itemID == "a")
        selection.retain(Self.hidden, in: .hidden)
        #expect(selection.anchor?.itemID == "a")
        selection.retain([], in: .visible)
        #expect(selection.anchor == nil)
    }

    @Test("The batch keeps the menu bar's left-to-right order: Always Hidden, Hidden, then Visible")
    func orderFollowsTheMenuBar() {
        let selection = selection([("c", .visible, .toggle), ("a", .visible, .toggle), ("h2", .hidden, .toggle), ("h1", .hidden, .toggle)])
        let order = selection.orderedItemIDs(in: [.visible: Self.visible, .hidden: Self.hidden])
        #expect(order == ["h1", "h2", "a", "c"])
    }

    @Test("Move entries leave out the section everything is already in and any that refuse")
    func moveTargetsSkipTheCurrentSection() {
        let all: [MenuBarSectionName] = [.visible, .hidden, .alwaysHidden]
        let inVisible = selection([("a", .visible, .replace), ("b", .visible, .toggle)])
        #expect(inVisible.moveTargets(enabledSections: all) { _ in true } == [.hidden, .alwaysHidden])
        #expect(inVisible.moveTargets(enabledSections: [.visible, .hidden]) { _ in true } == [.hidden])
        #expect(inVisible.moveTargets(enabledSections: all) { $0 != .hidden } == [.alwaysHidden])

        let mixed = selection([("a", .visible, .replace), ("h1", .hidden, .toggle)])
        #expect(mixed.moveTargets(enabledSections: all) { _ in true } == all)

        #expect(LayoutSelection().moveTargets(enabledSections: all) { _ in true }.isEmpty)
    }

    @Test("A drop lands after the nearest unselected item before it, or at the start")
    func dropPlacement() {
        let order = ["a", "b", "c", "d"]
        #expect(LayoutSelection.placement(insertingAt: 2, in: order, selected: ["x"]) == .after("b"))
        #expect(LayoutSelection.placement(insertingAt: 2, in: order, selected: ["b"]) == .after("a"))
        #expect(LayoutSelection.placement(insertingAt: 2, in: order, selected: ["a", "b"]) == .start)
        #expect(LayoutSelection.placement(insertingAt: 0, in: order, selected: []) == .start)
        #expect(LayoutSelection.placement(insertingAt: 9, in: order, selected: []) == .after("d"))
        #expect(LayoutSelection.placement(insertingAt: -1, in: order, selected: []) == .start)
    }
}
