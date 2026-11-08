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

    @Test("Sections keep their order and bar order, drop when empty, and filter by name")
    func sectionsAndFilter() {
        let visible = Self.items(["Alpha", "Beta"])
        let hidden = Self.items(["Gamma"])
        let all = LayoutItemList.sections(from: [.visible: visible, .hidden: hidden, .alwaysHidden: []], order: [.visible, .hidden, .alwaysHidden], query: "")
        #expect(all.map(\.name) == [.visible, .hidden])
        #expect(all[0].rows.map(\.name) == ["Alpha", "Beta"])

        let filtered = LayoutItemList.sections(from: [.visible: visible, .hidden: hidden], order: [.visible, .hidden], query: " gam ")
        #expect(filtered.map(\.name) == [.hidden])
        #expect(filtered[0].rows.map(\.name) == ["Gamma"])
        #expect(LayoutItemList.sections(from: [.visible: visible], order: [.visible], query: "zzz").isEmpty)
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

    @Test("At its minimum size the bars span the window, and the list and the tabs below each get a usable width")
    func minimumSizeFitsAll() {
        let minimum = LayoutDashboardMetrics.windowMinSize
        #expect(minimum.width >= LayoutDashboardMetrics.listMinWidth + LayoutDashboardMetrics.tabsMinWidth)
        #expect(LayoutDashboardMetrics.listMinWidth >= 280, "room for a picture, a name and an app name")
        #expect(LayoutDashboardMetrics.tabsMinWidth >= 320, "room for the Groups, Spacers and Apple's items tabs")
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
