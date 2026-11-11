//
//  LayoutDashboardEditorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Layout window checkboxes and item editor", .serialized, .scratchDefaults)
struct LayoutDashboardEditorTests {
    private typealias World = LayoutEditorWorld

    private static func units(_ items: [MenuBarItem]) -> [LayoutSelection.Unit] {
        items.map { LayoutSelection.Unit(memberIDs: [$0.uniqueIdentifier], isSelectable: true) }
    }

    /// A selection whose moves are recorded instead of run, reporting each as done.
    private static func recordingSelection(_ moves: @escaping (LayoutBatchMove) -> Void) -> LayoutSelectionModel {
        let selection = LayoutSelectionModel(announce: { _ in })
        selection.makeMover = { _ in
            { command in
                moves(command)
                return .moved(LayoutBatchMovePlan(
                    itemIDs: command.itemIDs,
                    source: .visible,
                    target: command.section,
                    previousTargetOrder: [],
                    targetOrder: command.itemIDs
                ))
            }
        }
        return selection
    }

    // MARK: Checkboxes

    @Test("Unchecking hides an item beside the divider, undoably; checking shows it beside the divider")
    func checkboxMovesAndUndoes() async {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([alpha], in: .visible)
        world.seat([beta], in: .hidden)
        var moves = [LayoutBatchMove]()
        let selection = Self.recordingSelection { moves.append($0) }
        selection.update(Self.units([alpha]), in: .visible)
        selection.update(Self.units([beta]), in: .hidden)
        world.appState.layoutUndo.removeAllActions()

        LayoutItemVisibility.setShown(false, rowID: alpha.uniqueIdentifier, in: .visible, selection: selection, appState: world.appState)
        for _ in 0 ..< 200 where moves.count < 1 || !world.appState.layoutUndo.canUndo {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(moves.first?.itemIDs == [alpha.uniqueIdentifier])
        #expect(moves.first?.section == .hidden)
        #expect(moves.first?.placement == .end, "next to the divider")
        #expect(world.appState.layoutUndo.canUndo, "the hide is in the shared history")

        selection.update(Self.units([beta]), in: .hidden)
        LayoutItemVisibility.setShown(true, rowID: beta.uniqueIdentifier, in: .hidden, selection: selection, appState: world.appState)
        for _ in 0 ..< 200 where moves.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(moves.last?.itemIDs == [beta.uniqueIdentifier])
        #expect(moves.last?.section == .visible)
        #expect(moves.last?.placement == .start, "next to the divider")
    }

    @Test("An item macOS keeps in place has a locked checkbox that says why; a movable one doesn't")
    func lockedCheckbox() {
        let clock = World.item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"))
        let alpha = World.item("Alpha")
        let reason = LayoutItemVisibility.lockReason(for: clock, in: .visible, experimentalSystemItemHiding: false)
        #expect(reason?.isEmpty == false)
        #expect(LayoutItemVisibility.lockReason(for: alpha, in: .visible, experimentalSystemItemHiding: false) == nil)
        #expect(LayoutItemVisibility.lockReason(for: alpha, in: .hidden, experimentalSystemItemHiding: false) == nil)
    }

    @Test("With several rows selected, one checkbox applies to them all; an unselected row moves alone")
    func checkboxAppliesToSelection() async {
        let world = World()
        let items = ["Alpha", "Beta", "Gamma"].map { World.item($0) }
        world.seat(items, in: .visible)
        var moves = [LayoutBatchMove]()
        let selection = Self.recordingSelection { moves.append($0) }
        selection.update(Self.units(items), in: .visible)
        selection.click(items[0].uniqueIdentifier, in: .visible, kind: .replace)
        selection.click(items[2].uniqueIdentifier, in: .visible, kind: .toggle)

        LayoutItemVisibility.setShown(false, rowID: items[2].uniqueIdentifier, in: .visible, selection: selection, appState: world.appState)
        for _ in 0 ..< 200 where moves.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(moves.first?.itemIDs == [items[0], items[2]].map(\.uniqueIdentifier))

        selection.update(Self.units(items), in: .visible)
        selection.click(items[0].uniqueIdentifier, in: .visible, kind: .replace)
        selection.click(items[2].uniqueIdentifier, in: .visible, kind: .toggle)
        LayoutItemVisibility.setShown(false, rowID: items[1].uniqueIdentifier, in: .visible, selection: selection, appState: world.appState)
        for _ in 0 ..< 200 where moves.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(moves.last?.itemIDs == [items[1].uniqueIdentifier])
    }

    // MARK: Editor

    @Test("The editor shows the selected item and its section, or a count and the shared section, or nothing")
    func editorContent() {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let gamma = World.item("Gamma")
        world.seat([alpha, beta], in: .visible)
        world.seat([gamma], in: .hidden)
        let cache = world.appState.itemManager.itemCache

        guard case .empty = LayoutItemEditorContent.make(selectedIDs: [], itemCache: cache) else {
            Issue.record("nothing selected shows the empty state")
            return
        }
        guard case let .single(item, section) = LayoutItemEditorContent.make(selectedIDs: [gamma.uniqueIdentifier], itemCache: cache) else {
            Issue.record("one item shows its fields")
            return
        }
        #expect(item.uniqueIdentifier == gamma.uniqueIdentifier)
        #expect(section == .hidden)

        guard case let .several(count, shared) = LayoutItemEditorContent.make(selectedIDs: [alpha, beta].map(\.uniqueIdentifier), itemCache: cache) else {
            Issue.record("several items show a count")
            return
        }
        #expect(count == 2)
        #expect(shared == .visible)
        guard case let .several(_, mixed) = LayoutItemEditorContent.make(selectedIDs: [alpha, gamma].map(\.uniqueIdentifier), itemCache: cache) else {
            Issue.record("several items show a count")
            return
        }
        #expect(mixed == nil, "no single section to show")
    }

    @Test("The editor's app details: a running app by name, Apple's items as part of macOS")
    func appDetails() {
        let alpha = World.item("Alpha")
        let details = LayoutItemAppDetails(item: alpha)
        #expect(details.isRunning, "the test process owns the item")
        #expect(!details.isPartOfMacOS)
        #expect(details.name?.isEmpty == false)

        let wifi = World.item(MenuBarItemTag(namespace: .string("com.apple.menuextra.wifi"), title: "WiFi"))
        #expect(LayoutItemAppDetails(item: wifi).isPartOfMacOS)
    }

    @Test("An editor showing an item stays idle: no selection or undo churn")
    func idleEditor() async throws {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha], in: .visible)
        let target = LayoutEditTarget(displayUUID: "D1", displayID: 1, spaceKey: "S1", displayName: "Display", spaceName: "Desktop 1")
        let model = LayoutDashboardModel(undoManager: world.appState.layoutUndo, readTarget: { target })
        model.selection.update(Self.units([alpha]), in: .visible)
        model.selection.click(alpha.uniqueIdentifier, in: .visible, kind: .replace)
        let host = NSHostingView(rootView: LayoutDashboardView(appState: world.appState, model: model))
        host.frame = NSRect(origin: .zero, size: LayoutDashboardMetrics.windowMinSize)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let selectionChanges = model.selection.changeCount
        let undoRefreshes = model.undo.refreshCount
        let canUndo = world.appState.layoutUndo.canUndo
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.selection.changeCount == selectionChanges, "the selection changed while idle")
        #expect(model.undo.refreshCount == undoRefreshes, "the undo state refreshed while idle")
        #expect(world.appState.layoutUndo.canUndo == canUndo, "showing the editor recorded an edit")
        _ = host
    }
}
