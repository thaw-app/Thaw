//
//  LayoutItemListBehaviourTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Layout window list keys, drops and moves", .serialized, .scratchDefaults)
struct LayoutItemListBehaviourTests {
    private typealias World = LayoutEditorWorld
    private typealias Entry = LayoutBatchMoveSnapshot.Entry

    private static func entry(_ id: String, group: String? = nil) -> Entry {
        Entry(id: id, isControlItem: false, groupID: group, assignableSections: Set(MenuBarSectionName.allCases), reordersInVisible: true)
    }

    private static func units(_ ids: [String]) -> [LayoutSelection.Unit] {
        ids.map { LayoutSelection.Unit(memberIDs: [$0], isSelectable: true) }
    }

    // MARK: Keys

    @Test("The keys match the bars', plus Home, End and the page keys")
    func keyMap() {
        func command(_ key: KeyEquivalent, _ characters: String = "", _ modifiers: EventModifiers = []) -> LayoutItemListCommand? {
            LayoutItemListCommand.command(for: key, characters: characters, modifiers: modifiers)?.command
        }
        #expect(command(.downArrow) == .step(1))
        #expect(LayoutItemListCommand.command(for: .upArrow, characters: "", modifiers: .shift)?.extends == true)
        #expect(command(.pageDown) == .page(1))
        #expect(command(.pageUp) == .page(-1))
        #expect(command(.home) == .edge(first: true))
        #expect(command(.end) == .edge(first: false))
        #expect(command(.leftArrow, "", .option) == .nudge(left: true))
        #expect(command(.rightArrow, "", .option) == .nudge(left: false))
        #expect(command(.upArrow, "", .option) == .adjacentSection(up: true))
        #expect(command(.downArrow, "", .option) == .adjacentSection(up: false))
        #expect(command(KeyEquivalent("2"), "2", .command) == .sectionNumber(2))
        #expect(command(KeyEquivalent("a"), "a", .command) == .selectAll)
        #expect(command(KeyEquivalent("z"), "z", .command) == .undo)
        #expect(command(KeyEquivalent("Z"), "Z", [.command, .shift]) == .redo)
        #expect(command(.space) == .showEditor)
        #expect(command(.return) == .menu)
        #expect(command(.leftArrow) == nil, "plain left and right are the bars', not the list's")
        #expect(command(KeyEquivalent("a"), "a") == nil, "typing passes through")
        #expect(command(.leftArrow, "", [.option, .command]) == nil)
    }

    @Test("The keys step from the row they last landed on, with or without Shift")
    func stepStartFollowsTheHead() {
        // A fresh selection steps from the anchor.
        #expect(LayoutItemList.stepStart(head: nil, anchor: "B", changeCount: 1) == "B")
        // The row the keys last landed on starts the next extend past the first row,
        // and a plain arrow after Shift+arrow carries on from there, as in Finder.
        #expect(LayoutItemList.stepStart(head: ("C", 1), anchor: "B", changeCount: 1) == "C")
        // A selection change elsewhere, such as a click in the bars, puts the keys back on the anchor.
        #expect(LayoutItemList.stepStart(head: ("C", 1), anchor: "B", changeCount: 2) == "B")
    }

    @Test("A Shift-click in a filtered list selects only the rows it shows")
    func shiftClickStaysInTheShownRows() {
        let items = ["Alpha", "Beta", "Gamma"].map { World.item($0) }
        let ids = items.map(\.uniqueIdentifier)
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(ids), in: .visible)
        func row(_ index: Int) -> LayoutItemListRow {
            LayoutItemListRow(id: ids[index], item: items[index], name: items[index].displayName, ownerName: nil, section: .visible)
        }
        let alpha = row(0), gamma = row(2)
        // The filter hides Beta.
        let shown: Set = [ids[0], ids[2]]

        LayoutItemList.click(alpha, kind: .replace, shownRowIDs: { shown }, selection: selection)
        LayoutItemList.click(gamma, kind: .extend, shownRowIDs: { shown }, selection: selection)
        #expect(Set(selection.orderedItemIDs) == shown)
    }

    @Test("Escape empties the filter, then closes; ⌘W closes; a field being typed in keeps Escape")
    func windowKeys() {
        func action(_ code: KeyCode, _ characters: String = "", _ flags: NSEvent.ModifierFlags = [], filter: String = "", editing: Bool = false) -> LayoutDashboardKeys.Action? {
            LayoutDashboardKeys.action(keyCode: code, characters: characters, flags: flags, filterText: filter, isEditingText: editing)
        }
        #expect(action(.escape, filter: "bat") == .clearFilter)
        #expect(action(.escape) == .close)
        #expect(action(.escape, editing: true) == nil)
        #expect(action(.w, "w", .command) == .close)
        #expect(action(.w, "w", .command, editing: true) == .close)
        #expect(action(.w, "w") == nil)
        #expect(action(.escape, "", .shift) == nil)
    }

    // MARK: Placement

    @Test("⌥-arrows step one place, hold at the ends, and step over a group as one")
    func nudge() {
        let entries = [Self.entry("A"), Self.entry("G1", group: "g"), Self.entry("G2", group: "g"), Self.entry("X"), Self.entry("C")]
        #expect(LayoutItemListPlacement.nudge(["X"], in: entries, left: true) == .after("A"), "past the whole group")
        #expect(LayoutItemListPlacement.nudge(["X"], in: entries, left: false) == .after("C"))
        #expect(LayoutItemListPlacement.nudge(["A"], in: entries, left: true) == nil)
        #expect(LayoutItemListPlacement.nudge(["C"], in: entries, left: false) == nil)
        #expect(LayoutItemListPlacement.nudge(["A"], in: entries, left: false) == .after("G2"))
        #expect(LayoutItemListPlacement.nudge(["G1", "G2"], in: entries, left: true) == .start)
        #expect(LayoutItemListPlacement.nudge(["Q"], in: entries, left: true) == nil, "not in this section")
    }

    @Test("A drop on a row lands just left of it")
    func dropPlacement() {
        let order = ["A", "B", "C", "D"]
        #expect(LayoutItemListPlacement.drop(["D"], before: "B", in: order) == .after("A"))
        #expect(LayoutItemListPlacement.drop(["D"], before: "A", in: order) == .start)
        #expect(LayoutItemListPlacement.drop(["A"], before: "C", in: order) == .after("B"))
        #expect(LayoutItemListPlacement.drop(["B"], before: "B", in: order) == nil)
        #expect(LayoutItemListPlacement.drop(["Z"], before: "Q", in: order) == nil)
    }

    @Test("⌥↑, ⌥↓ and ⌘number pick the sections that are on")
    func sections() {
        let all: [MenuBarSectionName?] = [.visible, .hidden, .alwaysHidden]
        #expect(LayoutItemListPlacement.adjacent(to: .hidden, up: true, destinations: all) == .visible)
        #expect(LayoutItemListPlacement.adjacent(to: .hidden, up: false, destinations: all) == .alwaysHidden)
        #expect(LayoutItemListPlacement.adjacent(to: .visible, up: true, destinations: all) == nil)
        #expect(LayoutItemListPlacement.adjacent(to: .hidden, up: false, destinations: [.visible, .hidden, nil]) == nil)
        #expect(LayoutItemListPlacement.numbered(3, destinations: [.visible, .hidden, nil]) == nil)
        #expect(LayoutItemListPlacement.numbered(1, destinations: all) == .visible)
    }

    // MARK: Moves

    @Test("A list move speaks when it lands and keeps the moved items selected for the next key")
    func moveKeepsSelection() async {
        let world = World()
        let items = ["Alpha", "Beta"].map { World.item($0) }
        world.seat(items, in: .visible)
        let ids = items.map(\.uniqueIdentifier)
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(ids), in: .visible)
        selection.click(ids[1], in: .visible, kind: .replace)
        var moved = false
        selection.makeMover = { _ in
            { command in
                moved = true
                return .moved(LayoutBatchMovePlan(itemIDs: command.itemIDs, source: .visible, target: .hidden, previousTargetOrder: [], targetOrder: command.itemIDs))
            }
        }
        LayoutItemVisibility.moveSelection(to: .hidden, selection: selection, appState: world.appState, keepsSelection: true)
        for _ in 0 ..< 100 where !moved {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(selection.orderedItemIDs.isEmpty, "cleared while the bars catch up")
        // The bars report the item in its new section.
        selection.update(Self.units([ids[0]]), in: .visible)
        selection.update(Self.units([ids[1]]), in: .hidden)
        #expect(selection.orderedItemIDs == [ids[1]])
        #expect(selection.anchorItemID == ids[1], "the keyboard keeps working from it")
        #expect(LayoutSelectionModel.movedAnnouncement(count: 1, to: .hidden) == "Moved 1 item to Hidden")
        #expect(LayoutSelectionModel.movedAnnouncement(count: 2, to: .visible) == "Moved 2 items to Visible")
    }

    @Test("A click drops a pending reselection, so a late bar update can't override it")
    func clickCancelsReselection() {
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(["A", "B"]), in: .visible)
        selection.reselect(["C"], in: .hidden)
        selection.click("A", in: .visible, kind: .replace)
        selection.update(Self.units(["C"]), in: .hidden)
        #expect(selection.orderedItemIDs == ["A"])
    }

    @Test("A right click and a Control-click ask for a row's menu; other clicks pass to the row")
    func menuClicks() {
        typealias MenuView = LayoutItemListMenuHost.MenuView
        #expect(MenuView.opensMenu(type: .rightMouseDown, modifiers: []))
        #expect(MenuView.opensMenu(type: .leftMouseDown, modifiers: [.control]))
        #expect(!MenuView.opensMenu(type: .leftMouseDown, modifiers: []))
        #expect(!MenuView.opensMenu(type: .leftMouseDown, modifiers: [.command]))
        #expect(!MenuView.opensMenu(type: .leftMouseUp, modifiers: [.control]))
    }

    @Test("Clearing or selecting drops a pending reselection too")
    func clearAndSelectCancelReselection() {
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(["A", "B"]), in: .visible)

        selection.reselect(["C"], in: .hidden)
        selection.clear()
        selection.update(Self.units(["C"]), in: .hidden)
        #expect(selection.orderedItemIDs.isEmpty, "Escape stays in force")

        selection.update(Self.units([]), in: .hidden)
        selection.reselect(["C"], in: .hidden)
        selection.select(["B"])
        selection.update(Self.units(["C"]), in: .hidden)
        #expect(selection.orderedItemIDs == ["B"])

        selection.update(Self.units([]), in: .hidden)
        selection.reselect(["C"], in: .hidden)
        selection.selectAll(among: ["A"])
        selection.update(Self.units(["C"]), in: .hidden)
        #expect(selection.orderedItemIDs == ["A"])
    }

    @Test("A drop selects what it carries; an empty one means the selection; unknown identifiers are refused")
    func dropSelects() {
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(["A", "B", "C"]), in: .visible)
        selection.click("A", in: .visible, kind: .replace)
        selection.click("C", in: .visible, kind: .toggle)
        #expect(LayoutItemListDrop.select([], in: selection) == ["A", "C"], "empty means the shared selection")
        #expect(LayoutItemListDrop.select(["C", "A"], in: selection) == ["A", "C"])
        #expect(LayoutItemListDrop.select(["B"], in: selection) == ["B"])
        #expect(LayoutItemListDrop.select(["some text"], in: selection) == nil)
    }

    @Test("Dragging an unselected row selects it alone and carries its identifier as the bars' drag type")
    func dragPayload() async {
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(["A", "B"]), in: .visible)
        selection.click("A", in: .visible, kind: .replace)
        let provider = LayoutItemListDrop.provider(for: "B", in: .visible, selection: selection)
        #expect(selection.orderedItemIDs == ["B"])
        #expect(LayoutItemListDrop.type.identifier == NSPasteboard.PasteboardType.layoutBarSelection.rawValue)
        let ids: [String] = await withCheckedContinuation { continuation in
            _ = LayoutItemListDrop.load([provider]) { continuation.resume(returning: $0) }
        }
        #expect(ids == ["B"])
    }

    // MARK: Window

    @Test("The subtitle reads the profile each time, so a Space that switches profile renames it")
    func liveProfileName() {
        var name: String? = "Work"
        let target = LayoutEditTarget(displayUUID: "D1", displayID: 1, spaceKey: "S1", displayName: "Display", spaceName: "Desktop 1")
        let model = LayoutDashboardModel(profileName: { name }, readTarget: { target })
        #expect(model.profileName == "Work")
        name = "Home"
        #expect(model.profileName == "Home")
    }

    @Test("Without a running backend, hiding isn't reported unavailable")
    func hidingUnavailable() {
        #expect(!InertSectionController().isHidingUnavailable)
    }
}
