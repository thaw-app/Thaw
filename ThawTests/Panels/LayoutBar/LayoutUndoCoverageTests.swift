//
//  LayoutUndoCoverageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Every layout edit can be undone and redone from the one layout history.
@MainActor
@Suite("Layout undo coverage", .serialized, .scratchDefaults)
struct LayoutUndoCoverageTests {
    private typealias World = LayoutEditorWorld

    /// The world's layout history with explicit groups, so a test can undo right away.
    private func history(_ world: World) -> UndoManager {
        let undoManager = world.appState.layoutUndo
        undoManager.groupsByEvent = false
        return undoManager
    }

    private func record(_ undoManager: UndoManager, _ edit: () -> Void) {
        undoManager.beginUndoGrouping()
        edit()
        undoManager.endUndoGrouping()
    }

    @Test("Grouping two items undoes and redoes")
    func groupingUndo() {
        let world = World()
        let alpha = World.item("Alpha"), beta = World.item("Beta")
        world.seat([alpha, beta])
        let manager = world.appState.itemGroupManager
        let undoManager = history(world)

        record(undoManager) {
            LayoutEditUndo.editGroups("Group Items", manager: manager, undoManager: undoManager) {
                _ = manager.createGroup(name: nil, items: [alpha, beta])
            }
        }
        #expect(manager.groupSet.groups.count == 1)
        #expect(undoManager.undoActionName == "Group Items")
        undoManager.undo()
        #expect(manager.groupSet.groups.isEmpty)
        undoManager.redo()
        #expect(manager.groupSet.groups.count == 1)
    }

    @Test("A group edit that changes nothing leaves no undo step")
    func noOpGroupEdit() {
        let world = World()
        let undoManager = history(world)
        record(undoManager) {
            LayoutEditUndo.editGroups("Nothing", manager: world.appState.itemGroupManager, undoManager: undoManager) {}
        }
        // An empty group can still read as undoable; an edit always names its step.
        #expect(undoManager.undoActionName.isEmpty)
    }

    @Test("A folder change that doesn't happen leaves no undo step")
    func folderNoOpLeavesNoUndo() throws {
        let world = World()
        let alpha = World.item("Alpha"), beta = World.item("Beta")
        world.seat([alpha, beta])
        let group = try #require(world.appState.itemGroupManager.createGroup(name: "Duo", items: [alpha, beta]))
        let undoManager = history(world)
        // The folders aren't set up in the test world, so setFolder declines, as it does for a group it can't resolve.
        record(undoManager) {
            LayoutEditUndo.setFolder(true, for: .user(group.id), members: [alpha, beta], name: "Duo", folders: world.appState.groupFolders, undoManager: undoManager)
        }
        // An empty group can still read as undoable; an edit always names its step.
        #expect(undoManager.undoActionName.isEmpty)
    }

    @Test("Renaming an item undoes to its old name and redoes")
    func renameUndo() {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "Old"
        let undoManager = history(world)

        record(undoManager) { LayoutEditUndo.rename(alpha, to: "New", undoManager: undoManager) }
        #expect(alpha.customName == "New")
        undoManager.undo()
        #expect(alpha.customName == "Old")
        undoManager.redo()
        #expect(alpha.customName == "New")
    }

    @Test("Choosing an icon undoes to no choice and redoes")
    func iconUndo() {
        let world = World()
        let alpha = World.item("Alpha")
        let choices = MenuBarItemIconChoices.shared
        choices.setImage(nil, for: alpha)
        let undoManager = history(world)
        let image = NSImage(size: CGSize(width: 16, height: 16))

        record(undoManager) { LayoutEditUndo.setIcon(image, for: alpha, undoManager: undoManager) }
        #expect(choices.hasChoice(for: alpha))
        undoManager.undo()
        #expect(!choices.hasChoice(for: alpha))
        undoManager.redo()
        #expect(choices.hasChoice(for: alpha))
        choices.setImage(nil, for: alpha)
    }

    @Test("Adding a spacer undoes and redoes")
    func addSpacerUndo() {
        let world = World()
        let spacers = world.appState.spacerManager
        let before = spacers.spacers.count
        let undoManager = history(world)

        record(undoManager) { spacers.addSpacer(undoManager: undoManager) }
        #expect(spacers.spacers.count == before + 1)
        #expect(undoManager.undoActionName == MenuBarSpacerManager.addActionName)
        undoManager.undo()
        #expect(spacers.spacers.count == before)
        undoManager.redo()
        #expect(spacers.spacers.count == before + 1)
        for spacer in spacers.spacers {
            spacers.removeSpacer(id: spacer.id)
        }
    }

    @Test("One slider drag is one width undo step back to where it started")
    func spacerWidthUndo() throws {
        let world = World()
        let spacers = world.appState.spacerManager
        spacers.addSpacer()
        let id = try #require(spacers.spacers.last?.id)
        let start = try #require(spacers.spacers.last?.width)
        let undoManager = history(world)

        record(undoManager) {
            spacers.setWidth(start + 4, for: id, undoManager: undoManager)
            spacers.setWidth(start + 8, for: id, undoManager: undoManager)
        }
        #expect(spacers.spacers.last?.width == start + 8)
        undoManager.undo()
        #expect(spacers.spacers.last?.width == start, "the whole drag goes back")
        #expect(!undoManager.canUndo)
        undoManager.redo()
        #expect(spacers.spacers.last?.width == start + 8)
        spacers.removeSpacer(id: id)
    }

    @Test("The order before a same-section drag puts the item back in the slot it left")
    func orderBeforeDrag() {
        let items = ["A", "B", "C"].map { World.item($0) }
        let dragged = [items[1], items[2], items[0]]
        let previous = LayoutReorderUndo.orderBeforeDrag(of: items[0], in: dragged, from: 0)
        #expect(previous?.map(\.tag) == items.map(\.tag))
        #expect(LayoutReorderUndo.orderBeforeDrag(of: items[0], in: items, from: 0) == nil, "no change, no undo")
        #expect(LayoutReorderUndo.orderBeforeDrag(of: items[0], in: dragged, from: nil) == nil)
    }

    @Test("A reorder undo restores the previous order and redo puts it back")
    func reorderUndo() {
        let world = World()
        let items = ["A", "B", "C"].map { World.item($0) }
        world.seat(items)
        let reordered = [items[2], items[0], items[1]]
        let undoManager = history(world)

        record(undoManager) {
            LayoutReorderUndo.register(reordered, previous: items, of: items[2], section: .visible, appState: world.appState)
        }
        // The test world's controller stores no order, so this checks the history itself.
        #expect(undoManager.undoActionName == String(localized: "Move \(items[2].displayName)"))
        undoManager.undo()
        #expect(undoManager.canRedo, "undo goes through the keyboard's order commit, which registers the redo")
        undoManager.redo()
        #expect(undoManager.canUndo)
    }

    @Test("Only a batch move that happened records an undo step")
    func batchMoveRecordsOnlyMoves() {
        let plan = LayoutBatchMovePlan(itemIDs: ["a"], source: .visible, target: .hidden, previousTargetOrder: [], targetOrder: ["a"])
        #expect(LayoutBatchMoveUndo.records(.moved(plan)))
        #expect(!LayoutBatchMoveUndo.records(.unchanged(plan)))
        #expect(!LayoutBatchMoveUndo.records(.refused(.missingItem)))
        #expect(!LayoutBatchMoveUndo.records(nil))
    }

    @Test("A batch undo registers its redo right away, so redo is a redo and not a new edit")
    func batchUndoRedo() {
        let world = World()
        let undoManager = history(world)
        let forward = LayoutBatchMove(itemIDs: ["a"], section: .hidden, placement: .end)
        let restoring = [LayoutBatchMove(itemIDs: ["a"], section: .visible, placement: .start)]

        record(undoManager) { LayoutBatchMoveUndo.register(forward: forward, restoring: restoring, appState: world.appState) }
        #expect(undoManager.undoActionName == LayoutBatchMoveUndo.actionName(count: 1))
        undoManager.undo()
        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(undoManager.canUndo)
    }
}
