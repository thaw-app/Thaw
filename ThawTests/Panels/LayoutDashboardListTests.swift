//
//  LayoutDashboardListTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Layout window list", .serialized, .scratchDefaults)
struct LayoutDashboardListTests {
    private typealias World = LayoutEditorWorld

    /// Items named by their titles, as the test process owns them all.
    private static func items(_ titles: [String]) -> [MenuBarItem] {
        let items = titles.map { World.item($0) }
        var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        for item in items {
            names[item.uniqueIdentifier] = item.title
        }
        Defaults.set(names, forKey: .menuBarItemCustomNames)
        return items
    }

    private static func units(_ items: [MenuBarItem]) -> [LayoutSelection.Unit] {
        items.map { LayoutSelection.Unit(memberIDs: [$0.uniqueIdentifier], isSelectable: true) }
    }

    // MARK: Rows and filter

    @Test("Sections keep their order and bar order, and drop when empty")
    func sectionsInOrder() {
        let visible = Self.items(["Alpha", "Beta"])
        let hidden = Self.items(["Gamma"])
        let all = LayoutItemList.sections(from: [.visible: visible, .hidden: hidden, .alwaysHidden: []], order: [.visible, .hidden, .alwaysHidden], query: "")
        #expect(all.map(\.name) == [.visible, .hidden])
        #expect(all[0].rows.map(\.name) == ["Alpha", "Beta"])
        #expect(all[1].rows.map(\.section) == [.hidden], "each row knows its section, for the badge and the moves")
    }

    @Test("A query ranks matches as search does, in one run without headings")
    func fuzzyFilter() {
        let visible = Self.items(["Battery", "Gamma Clock"])
        let hidden = Self.items(["Gammaray", "Backup"])
        let items: [MenuBarSectionName: [MenuBarItem]] = [.visible: visible, .hidden: hidden]
        let ranked = LayoutItemList.sections(from: items, order: [.visible, .hidden], query: " gam ")
        #expect(ranked.count == 1)
        #expect(ranked[0].name == nil, "matches across sections aren't split by heading")
        #expect(ranked[0].rows.map(\.name).prefix(2).sorted() == ["Gamma Clock", "Gammaray"], "prefix matches rank first")
        #expect(ranked[0].rows.first { $0.name == "Gammaray" }?.section == .hidden)

        let typo = LayoutItemList.sections(from: items, order: [.visible, .hidden], query: "batery")
        #expect(typo.first?.rows.first?.name == "Battery", "a typo still finds the item, as in search")
        #expect(LayoutItemList.sections(from: items, order: [.visible, .hidden], query: "zzzzqq").isEmpty)
    }

    @Test("The scope keeps one section, with or without a query, and offers only sections that are on")
    func scope() {
        let visible = Self.items(["Alpha"])
        let hidden = Self.items(["Alpine"])
        let items: [MenuBarSectionName: [MenuBarItem]] = [.visible: visible, .hidden: hidden]
        let order: [MenuBarSectionName] = [.visible, .hidden]
        #expect(LayoutItemList.sections(from: items, order: order, query: "", scope: .hidden).map(\.name) == [.hidden])
        #expect(LayoutItemList.sections(from: items, order: order, query: "al", scope: .visible).flatMap(\.rows).map(\.name) == ["Alpha"])
        #expect(LayoutItemList.sections(from: items, order: order, query: "", scope: .alwaysHidden).isEmpty)
        #expect(LayoutItemListScope.offered(enabled: [.visible, .hidden]) == [.all, .visible, .hidden])
    }

    @Test("The count says items, or matches while filtering")
    func countText() {
        #expect(LayoutItemListText.count(1, isFiltered: false) == "1 item")
        #expect(LayoutItemListText.count(3, isFiltered: true) == "3 matches")
    }

    @Test("The arrows step through the rows and hold at the ends")
    func stepping() {
        let rows = LayoutItemList.sections(from: [.visible: Self.items(["A1", "B1", "C1"])], order: [.visible], query: "")[0].rows
        #expect(LayoutItemList.step(from: nil, by: 1, in: rows)?.name == "A1")
        #expect(LayoutItemList.step(from: rows[0].id, by: 1, in: rows)?.name == "B1")
        #expect(LayoutItemList.step(from: rows[2].id, by: 1, in: rows)?.name == "C1")
        #expect(LayoutItemList.step(from: rows[0].id, by: -1, in: rows)?.name == "A1")
    }

    // MARK: Shared selection

    @Test("A click in the list shows in the bars, and a click in a bar shows in the list: one model")
    func sharedSelection() {
        let items = Self.items(["Alpha", "Beta", "Gamma"])
        let selection = LayoutSelectionModel(announce: { _ in })
        // What a bar reports as it draws.
        selection.update(Self.units(items), in: .visible)

        // The list clicks Alpha; the bar asks the same model.
        selection.click(items[0].uniqueIdentifier, in: .visible, kind: .replace)
        #expect(selection.contains(items[0].uniqueIdentifier))

        // The bar ⌘-clicks Gamma; the list reads it back.
        selection.click(items[2].uniqueIdentifier, in: .visible, kind: .toggle)
        #expect(selection.orderedItemIDs == [items[0], items[2]].map(\.uniqueIdentifier))

        // ⇧-click from the anchor extends across the row in between.
        selection.click(items[0].uniqueIdentifier, in: .visible, kind: .replace)
        selection.click(items[2].uniqueIdentifier, in: .visible, kind: .extend)
        #expect(selection.count == 3)
        #expect(selection.anchorItemID == items[0].uniqueIdentifier)
    }

    @Test("⌘A selects every item the bars show")
    func selectAll() {
        let visible = Self.items(["Alpha", "Beta"])
        let hidden = Self.items(["Gamma"])
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(visible), in: .visible)
        selection.update(Self.units(hidden), in: .hidden)
        selection.selectAll()
        #expect(selection.count == 3)
    }

    @Test("⌘A in a filtered list selects only the rows it shows, so a move can't take the hidden ones")
    func selectAllFiltered() {
        let visible = Self.items(["Alpha", "Beta"])
        let hidden = Self.items(["Gamma", "Delta"])
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(visible), in: .visible)
        selection.update(Self.units(hidden), in: .hidden)
        let rows = LayoutItemList.sections(from: [.visible: visible, .hidden: hidden], order: [.visible, .hidden], query: "gamma")
            .flatMap(\.rows)
        #expect(rows.map(\.name) == ["Gamma"])
        selection.selectAll(among: Set(rows.map(\.id)))
        #expect(selection.orderedItemIDs == [hidden[0].uniqueIdentifier])
        #expect(selection.command(to: .visible, placement: .end)?.itemIDs == [hidden[0].uniqueIdentifier])
    }

    @Test("⌘A over a filtered group member brings the whole group, as a click on it does")
    func selectAllFilteredGroup() {
        let items = Self.items(["Alpha", "Beta", "Gamma"])
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update([
            LayoutSelection.Unit(memberIDs: [items[0].uniqueIdentifier, items[1].uniqueIdentifier], isSelectable: true),
            LayoutSelection.Unit(memberIDs: [items[2].uniqueIdentifier], isSelectable: true),
        ], in: .visible)
        selection.selectAll(among: [items[1].uniqueIdentifier])
        #expect(selection.orderedItemIDs == [items[0], items[1]].map(\.uniqueIdentifier))
    }

    // MARK: Actions and undo

    @Test("A list action moves every selected item in one batch, and lands in the layout history")
    func actionAppliesToTheSelection() async {
        let world = World()
        let items = Self.items(["Alpha", "Beta", "Gamma"])
        world.seat(items, in: .visible)
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(items), in: .visible)
        selection.click(items[0].uniqueIdentifier, in: .visible, kind: .replace)
        selection.click(items[2].uniqueIdentifier, in: .visible, kind: .toggle)

        var moved: LayoutBatchMove?
        selection.makeMover = { _ in
            { command in
                moved = command
                return .moved(LayoutBatchMovePlan(
                    itemIDs: command.itemIDs,
                    source: .visible,
                    target: command.section,
                    previousTargetOrder: [],
                    targetOrder: command.itemIDs
                ))
            }
        }
        world.appState.layoutUndo.removeAllActions()
        LayoutSelectionActions(selection: selection, appState: world.appState).move(to: .hidden, placement: .end)
        for _ in 0 ..< 100 where !world.appState.layoutUndo.canUndo {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(moved?.itemIDs == [items[0], items[2]].map(\.uniqueIdentifier))
        #expect(moved?.section == .hidden)
        #expect(world.appState.layoutUndo.canUndo, "the move is undoable from the shared history")
        #expect(world.appState.layoutUndo.undoActionName == LayoutBatchMoveUndo.actionName(count: 2))
        #expect(selection.orderedItemIDs.isEmpty, "a move clears the selection, as in the bars")
    }

    @Test("A refused list move leaves nothing to undo")
    func refusedMoveLeavesNoStep() async {
        let world = World()
        let items = Self.items(["Alpha"])
        world.seat(items, in: .visible)
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.update(Self.units(items), in: .visible)
        selection.click(items[0].uniqueIdentifier, in: .visible, kind: .replace)
        var ran = false
        selection.makeMover = { _ in
            { command in
                ran = true
                return .refused(.controlItem(command.itemIDs[0]))
            }
        }
        world.appState.layoutUndo.removeAllActions()
        LayoutSelectionActions(selection: selection, appState: world.appState).move(to: .hidden, placement: .end)
        for _ in 0 ..< 100 where !ran {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(ran)
        #expect(!world.appState.layoutUndo.canUndo)
    }

    // MARK: Idle and size

    @Test("An open window with nothing happening stays idle: no selection or undo churn")
    func idleWindow() async throws {
        let world = World()
        world.seat(Self.items(["Alpha", "Beta"]), in: .visible)
        let target = LayoutEditTarget(displayUUID: "D1", displayID: 1, spaceKey: "S1", displayName: "Display", spaceName: "Desktop 1")
        let model = LayoutDashboardModel(undoManager: world.appState.layoutUndo, readTarget: { target })
        let host = NSHostingView(rootView: LayoutDashboardView(appState: world.appState, model: model))
        host.frame = NSRect(origin: .zero, size: LayoutDashboardMetrics.windowMinSize)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let selectionChanges = model.selection.changeCount
        let undoRefreshes = model.undo.refreshCount
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.selection.changeCount == selectionChanges, "the selection changed while idle")
        #expect(model.undo.refreshCount == undoRefreshes, "the undo state refreshed while idle")
        _ = host
    }

    @Test("At its minimum size the bars span the window, and the list and the editor below each get a usable width")
    func minimumSizeFitsAll() {
        let minimum = LayoutDashboardMetrics.windowMinSize
        #expect(minimum.width >= LayoutDashboardMetrics.listMinWidth + LayoutDashboardMetrics.editorMinWidth)
        #expect(LayoutDashboardMetrics.listMinWidth >= 280, "room for a checkbox, a picture, a name and an app name")
        #expect(LayoutDashboardMetrics.editorMinWidth >= 320, "room for the editor's labelled rows")
        #expect(minimum.width >= 600, "the bars span the window, so they get its whole width")
        #expect(minimum.height >= LayoutDashboardMetrics.barsHeight(sections: 3) + 280, "room for all three bars and a useful list under them")

        let world = World()
        world.seat(Self.items(["Alpha"]), in: .visible)
        let target = LayoutEditTarget(displayUUID: "D1", displayID: 1, spaceKey: "S1", displayName: "Display", spaceName: "Desktop 1")
        let model = LayoutDashboardModel(readTarget: { target })
        let host = NSHostingView(rootView: LayoutDashboardView(appState: world.appState, model: model))
        host.frame = NSRect(origin: .zero, size: minimum)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= minimum.width + 1, "the content asks for no more than the window's minimum")
    }
}
