//
//  LayoutDesignPassTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Layout tiles show hover and press, a wobble stays a click, and moves into another section and
/// ungroups can be undone like their keyboard counterparts.
@MainActor
@Suite("Layout design pass", .serialized, .scratchDefaults)
struct LayoutDesignPassTests {
    @Test("Hover and press each draw a wash, the press stronger")
    func washFollowsPointer() {
        var pointer = LayoutTilePointer()
        #expect(pointer.washAlpha == nil)
        pointer.isHovered = true
        #expect(pointer.washAlpha == 0.12)
        pointer.press(at: .zero)
        #expect(pointer.washAlpha == 0.25)
        pointer.exit()
        #expect(pointer.washAlpha == nil)
    }

    @Test("A wobble under three points stays a click; past it the gesture is a drag")
    func dragThreshold() {
        var pointer = LayoutTilePointer()
        pointer.press(at: CGPoint(x: 10, y: 10))
        let wobble = pointer.drag(to: CGPoint(x: 12, y: 11))
        #expect(!wobble)
        #expect(pointer.isClickCandidate)
        let drag = pointer.drag(to: CGPoint(x: 13, y: 10))
        #expect(drag)
        #expect(!pointer.isClickCandidate)
        let releasedAfterDrag = pointer.release()
        #expect(!releasedAfterDrag, "a drag doesn't open the inspector")

        pointer.press(at: .zero)
        let releasedInPlace = pointer.release()
        #expect(releasedInPlace, "a press released in place clicks")
        #expect(!pointer.isPressed)
    }

    @Test("A drag with no press on record starts at once")
    func dragWithoutPress() {
        var pointer = LayoutTilePointer()
        let began = pointer.drag(to: .zero)
        #expect(began)
    }

    @Test("The unresponsive badge names the app and why it can't move")
    func unresponsiveHelp() {
        let help = LayoutBarItemView.unresponsiveHelp(appName: "Rex")
        #expect(help.hasPrefix("Rex"))
        #expect(help.contains("can’t be moved"))
    }

    @Test("Moving an item into another section registers an undo; a same-section move doesn't")
    func sectionMoveUndo() {
        let world = LayoutEditorWorld()
        let item = LayoutEditorWorld.item("Alpha")
        let sameSection = UndoManager()
        LayoutSectionMoveUndo.registerUndo(of: item, from: .visible, to: .visible, appState: world.appState, undoManager: sameSection)
        #expect(!sameSection.canUndo)

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        LayoutSectionMoveUndo.setSection(
            .hidden, of: item, from: .visible,
            controller: nil,
            appState: world.appState, undoManager: undoManager
        )
        undoManager.endUndoGrouping()
        #expect(undoManager.canUndo)
        #expect(undoManager.undoActionName == String(localized: "Move \(item.displayName)"))
        undoManager.undo()
    }

    @Test("Undoing an ungroup brings the group back with its name")
    func ungroupUndo() throws {
        let world = LayoutEditorWorld()
        let alpha = LayoutEditorWorld.item("Alpha"), beta = LayoutEditorWorld.item("Beta")
        world.seat([alpha, beta])
        let manager = world.appState.itemGroupManager
        let group = try #require(manager.createGroup(name: "Duo", items: [alpha, beta]))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        UngroupUndo.ungroup(.user(group.id), name: "Duo", manager: manager, folders: world.appState.groupFolders, undoManager: undoManager)
        undoManager.endUndoGrouping()
        #expect(manager.groupSet.groups.isEmpty)
        #expect(undoManager.undoActionName == UngroupUndo.actionName("Duo"))

        undoManager.undo()
        #expect(manager.groupSet.groups.first?.name == "Duo")
        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(manager.groupSet.groups.isEmpty)
    }
}
