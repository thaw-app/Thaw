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

    /// An earlier edit at the bottom of the history, so a test can see exactly what sits on top of it.
    private func recordEarlierEdit(_ undoManager: UndoManager, in world: World) {
        record(undoManager) {
            undoManager.registerUndo(withTarget: world.appState) { _ in }
            undoManager.setActionName(Self.earlierEdit)
        }
    }

    private static let earlierEdit = "Earlier Edit"

    /// Whether edit registers an undo step. An empty group would itself read as a step, so this
    /// groups by event instead: a registration opens a group, which nothing else here does.
    private func registersUndo(_ undoManager: UndoManager, _ edit: () -> Void) -> Bool {
        undoManager.groupsByEvent = true
        defer { undoManager.groupsByEvent = false }
        edit()
        return undoManager.groupingLevel > 0
    }

    /// The control item, seated in Visible. Hidden and Always Hidden refuse it, so a move between
    /// them stops at the gate here instead of reaching the menu bar.
    private func refusingItem(_ world: World) throws -> MenuBarItem {
        let control = World.item(.visibleControlItem)
        world.seat([control])
        for section in [MenuBarSection.Name.hidden, .alwaysHidden] {
            try #require(!MenuBarBackendProvider.current.canAssign(control, to: section, experimentalSystemItemHiding: false))
        }
        return control
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

    @Test("The order before a same-section drag is the captured drag-start order")
    func orderBeforeDrag() {
        let items = ["A", "B", "C"].map { World.item($0) }
        let dragged = [items[1], items[2], items[0]]
        #expect(LayoutReorderUndo.orderBeforeDrag(items, matching: dragged)?.map(\.tag) == items.map(\.tag))
        #expect(LayoutReorderUndo.orderBeforeDrag(items, matching: items) == nil, "no change, no undo")
        #expect(LayoutReorderUndo.orderBeforeDrag(nil, matching: dragged) == nil)
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

    @Test("An undo step whose anchor has gone puts the item at the end of its old section")
    func undoStepFallsBackWhenAnchorIsGone() async {
        let plan = LayoutBatchMovePlan(itemIDs: ["b"], source: .hidden, target: .visible, previousTargetOrder: ["c"], targetOrder: ["c", "b"])
        var asked = [LayoutBatchMove]()
        let step = LayoutBatchMove(itemIDs: ["b"], section: .visible, placement: .after("a"))

        let outcome = await LayoutBatchMoveUndo.run(step) { move in
            asked.append(move)
            return move.afterID == "a" ? .refused(.unknownAnchor("a")) : .moved(plan)
        }

        #expect(outcome == .moved(plan))
        #expect(asked == [step, LayoutBatchMove(itemIDs: ["b"], section: .visible, placement: .end)])
    }

    @Test("An undo step that goes through, or is refused for another reason, is not retried")
    func undoStepIsNotRetriedOtherwise() async {
        let plan = LayoutBatchMovePlan(itemIDs: ["b"], source: .hidden, target: .visible, previousTargetOrder: [], targetOrder: ["b"])
        let step = LayoutBatchMove(itemIDs: ["b"], section: .visible, placement: .start)
        for answer in [LayoutBatchMoveOutcome.moved(plan), .refused(.moveRefused)] {
            var calls = 0
            let outcome = await LayoutBatchMoveUndo.run(step) { _ in
                calls += 1
                return answer
            }
            #expect(outcome == answer)
            #expect(calls == 1)
        }
    }

    @Test("A refused undo step is reported; steps that moved or changed nothing are not")
    func refusedUndoIsReported() {
        let plan = LayoutBatchMovePlan(itemIDs: ["a"], source: .visible, target: .hidden, previousTargetOrder: [], targetOrder: ["a"])
        #expect(LayoutBatchMoveUndo.refusal(for: [.moved(plan), .unchanged(plan)]) == nil)
        #expect(LayoutBatchMoveUndo.refusal(for: []) == nil)
        #expect(LayoutBatchMoveUndo.refusal(for: [.moved(plan), .refused(.moveRefused)]) != nil)
    }

    @Test("The registration probe sees a step being registered")
    func probeSeesARegistration() {
        let world = World()
        let undoManager = history(world)
        #expect(registersUndo(undoManager) { undoManager.registerUndo(withTarget: world.appState) { _ in } })
        undoManager.endUndoGrouping()
    }

    @Test("Undoing a menu move puts its redo on top and adds no undo step when the undone move lands")
    func menuMoveUndoAddsNoStep() throws {
        let world = World()
        let control = try refusingItem(world)
        let undoManager = history(world)
        recordEarlierEdit(undoManager, in: world)

        // The menu's move landed, Always Hidden to Hidden, and asked for undo.
        record(undoManager) {
            MenuBarSearchItemActions.recordMoveUndo(
                of: control, groupMembers: nil, from: .alwaysHidden, to: .hidden,
                committed: true, recordsUndo: true, appState: world.appState
            )
        }
        #expect(undoManager.undoActionName == String(localized: "Move \(control.displayName)"))

        undoManager.undo()
        #expect(undoManager.canRedo)
        #expect(undoManager.undoActionName == Self.earlierEdit)

        // The undo runs the shared move without asking for undo; its landing adds nothing.
        #expect(!registersUndo(undoManager) {
            MenuBarSearchItemActions.recordMoveUndo(
                of: control, groupMembers: nil, from: .hidden, to: .alwaysHidden,
                committed: true, recordsUndo: false, appState: world.appState
            )
        })
        #expect(undoManager.canRedo, "a new step would have cleared the redo")
        #expect(undoManager.undoActionName == Self.earlierEdit)
    }

    @Test("A move that didn't land records no undo step, even when asked")
    func unlandedMoveRecordsNothing() throws {
        let world = World()
        let control = try refusingItem(world)
        let undoManager = history(world)
        recordEarlierEdit(undoManager, in: world)
        for committed in [false, nil] as [Bool?] {
            #expect(!registersUndo(undoManager) {
                MenuBarSearchItemActions.recordMoveUndo(
                    of: control, groupMembers: nil, from: .alwaysHidden, to: .hidden,
                    committed: committed, recordsUndo: true, appState: world.appState
                )
            })
        }
        #expect(undoManager.undoActionName == Self.earlierEdit)
    }

    @Test("A keyboard section move is one undo step")
    func keyboardSectionMoveIsOneStep() throws {
        let world = World()
        let control = try refusingItem(world)
        let undoManager = history(world)
        recordEarlierEdit(undoManager, in: world)

        record(undoManager) {
            LayoutBarKeyboard.performSectionMove(
                tag: control.tag, from: .alwaysHidden, to: .hidden,
                appState: world.appState, undoManager: undoManager, actionName: "Keyboard Move"
            )
        }
        // The shared move it runs lands without asking for undo.
        #expect(!registersUndo(undoManager) {
            MenuBarSearchItemActions.recordMoveUndo(
                of: control, groupMembers: nil, from: .alwaysHidden, to: .hidden,
                committed: true, recordsUndo: false, appState: world.appState
            )
        })
        #expect(undoManager.undoActionName == "Keyboard Move")
        undoManager.undo()
        #expect(undoManager.undoActionName == Self.earlierEdit, "one undo reaches the earlier edit")
        #expect(undoManager.redoActionName == "Keyboard Move")
    }

    @Test("Moving all of an app's items undoes and redoes as one step")
    func moveAllUndoRedo() throws {
        let world = World()
        let control = try refusingItem(world)
        let undoManager = history(world)
        recordEarlierEdit(undoManager, in: world)

        record(undoManager) {
            LayoutSectionMoveUndo.registerMoves(
                back: [.alwaysHidden: [control.tag]], forward: [.hidden: [control.tag]], appState: world.appState
            )
        }
        #expect(undoManager.undoActionName == LayoutBatchMoveUndo.actionName(count: 1))
        undoManager.undo()
        #expect(undoManager.undoActionName == Self.earlierEdit)
        #expect(undoManager.redoActionName == LayoutBatchMoveUndo.actionName(count: 1))
        undoManager.redo()
        #expect(undoManager.undoActionName == LayoutBatchMoveUndo.actionName(count: 1))
        #expect(!undoManager.canRedo)
    }

    @Test("Moving items that were already in the section leaves no undo step")
    func moveAllWithinSectionRecordsNothing() {
        let world = World()
        let alpha = World.item("Alpha")
        let undoManager = history(world)
        recordEarlierEdit(undoManager, in: world)
        #expect(!registersUndo(undoManager) {
            LayoutSectionMoveUndo.registerMoves(back: [.hidden: [alpha.tag]], forward: [.hidden: [alpha.tag]], appState: world.appState)
        })
        #expect(undoManager.undoActionName == Self.earlierEdit)
    }
}
