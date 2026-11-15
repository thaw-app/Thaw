//
//  LayoutDashboardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Layout window", .serialized, .scratchDefaults)
struct LayoutDashboardTests {
    private static func target(
        display: String = "D1",
        id: CGDirectDisplayID = 1,
        space: String? = "S13",
        name: String = "Studio Display",
        spaceName: String? = "Desktop 13"
    ) -> LayoutEditTarget {
        LayoutEditTarget(displayUUID: display, displayID: id, spaceKey: space, displayName: name, spaceName: spaceName)
    }

    // MARK: Pinning

    @Test("The bar the window opened on stays editable, and its names refresh")
    func sameTargetEditable() {
        var pin = LayoutTargetPin(Self.target())
        pin.observe(Self.target(name: "Studio Display (2)"))
        #expect(pin.isEditable)
        #expect(pin.pinned.displayName == "Studio Display (2)")
    }

    @Test("Another Space or another display makes the bars read-only, naming where you are")
    func elsewhereReadOnly() {
        var pin = LayoutTargetPin(Self.target())
        let otherSpace = Self.target(space: "S2", spaceName: "Desktop 2")
        pin.observe(otherSpace)
        #expect(!pin.isEditable)
        #expect(pin.state == .elsewhere(current: otherSpace))
        #expect(pin.pinned.spaceKey == "S13", "the target never moves on its own")

        var displays = LayoutTargetPin(Self.target())
        displays.observe(Self.target(display: "D2", id: 2, name: "Built-in Display"))
        #expect(!displays.isEditable)

        pin.observe(Self.target())
        #expect(pin.isEditable, "switching back edits again")
    }

    @Test("A Space the window server hasn't listed doesn't block editing")
    func unlistedSpace() {
        var pin = LayoutTargetPin(Self.target(space: nil, spaceName: nil))
        pin.observe(Self.target())
        #expect(pin.isEditable)
        #expect(pin.pinned.spaceKey == "S13", "the target learns its Space once listed")
    }

    @Test("A display ID is compared only when a UUID is missing")
    func displayIdentity() {
        #expect(Self.target(display: "D1", id: 1).isSameBar(as: Self.target(display: "D1", id: 7)))
        let noUUID = LayoutEditTarget(displayUUID: nil, displayID: 1, spaceKey: "S13", displayName: "A", spaceName: nil)
        #expect(noUUID.isSameBar(as: Self.target(id: 1)))
        #expect(!noUUID.isSameBar(as: Self.target(id: 2)))
    }

    @Test("Retargeting edits the bar you're on")
    func retarget() {
        var pin = LayoutTargetPin(Self.target())
        pin.observe(Self.target(space: "S2", spaceName: "Desktop 2"))
        pin.retargetToCurrent()
        #expect(pin.isEditable)
        #expect(pin.pinned.spaceName == "Desktop 2")
    }

    @Test("The model follows each Space or display change it is sent")
    func modelFollowsChanges() async {
        var current = Self.target()
        let changes = PassthroughSubject<Void, Never>()
        let model = LayoutDashboardModel(readTarget: { current }, changes: changes)
        #expect(model.pin.isEditable)
        current = Self.target(space: "S2", spaceName: "Desktop 2")
        changes.send()
        for _ in 0 ..< 50 where model.pin.isEditable {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.pin.isEditable)
        model.retargetToCurrent()
        #expect(model.pin.isEditable)
    }

    // MARK: Text

    @Test("The banner names Spaces when they differ, and displays otherwise")
    func bannerText() {
        let pinned = Self.target()
        #expect(LayoutDashboardText.elsewhere(pinned: pinned, current: Self.target(space: "S2", spaceName: "Desktop 2"))
            == "You're on Desktop 2. Switch back to Desktop 13, or edit this one instead.")
        #expect(LayoutDashboardText.elsewhere(pinned: pinned, current: Self.target(display: "D2", id: 2, space: "S13", name: "Built-in Display"))
            == "You're on Built-in Display. Switch back to Studio Display, or edit this one instead.")
        #expect(LayoutDashboardText.target(pinned) == "Desktop 13, Studio Display")
        #expect(LayoutDashboardText.target(Self.target(spaceName: nil)) == "Studio Display")
        #expect(LayoutDashboardText.title(profileName: "Work") == "Editing Work")
        #expect(LayoutDashboardText.title(profileName: nil) == "Editing the current layout")
    }

    // MARK: Migration

    @Test("The reorder editor's hidden flag is removed, harmlessly again, and nothing else")
    func removesReorderFlag() throws {
        let suiteName = ScratchDefaults.name("LayoutDashboardTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        defaults.set(true, forKey: MigrationManager.reorderEditorFlagKey)
        defaults.set(true, forKey: "RememberSearchQuery")
        for _ in 0 ..< 2 {
            MigrationManager().removeReorderEditorFlag(from: defaults)
            #expect(defaults.persistentDomain(forName: suiteName)?[MigrationManager.reorderEditorFlagKey] == nil)
        }
        #expect(defaults.bool(forKey: "RememberSearchQuery"))
    }

    // MARK: Pop Out

    @Test("Pop Out opens the Layout window, and closing it ends the presentation")
    func popOutOpensWindow() throws {
        let world = LayoutEditorWorld()
        let panel = MenuBarLayoutEditorPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        let screen = try #require(NSScreen.main)
        panel.showWindow(on: screen)
        #expect(panel.isShown)
        #expect(world.appState.navigationState.isLayoutEditorPresented)
        panel.close()
        #expect(!panel.isShown)
        #expect(!world.appState.navigationState.isLayoutEditorPresented)
    }
}

@MainActor
@Suite("Layout window undo")
struct LayoutDashboardUndoTests {
    @Test("Reading the history doesn't make the state read it again, so an idle window stays idle")
    func noFeedbackLoop() async throws {
        let state = LayoutUndoState(undoManager: UndoManager())
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.refreshCount < 5, "refreshed \(state.refreshCount) times while idle")
    }

    @Test("The toolbar follows the layout history: enabled with a step, named after it, and undo then redo work")
    func followsTheHistory() {
        let history = UndoManager()
        history.groupsByEvent = false
        let state = LayoutUndoState(undoManager: history)
        #expect(!state.canUndo)
        #expect(!state.canRedo)

        let box = UndoBox(history: history)
        history.beginUndoGrouping()
        box.set(1)
        history.endUndoGrouping()
        state.refresh()
        #expect(state.canUndo)
        #expect(state.undoTitle == history.undoMenuItemTitle)

        state.undo()
        #expect(box.value == 0)
        #expect(state.canRedo)
        #expect(!state.canUndo)

        state.redo()
        #expect(box.value == 1)
    }
}

/// A value whose every change registers its inverse, as layout edits do, so redo has something to run.
@MainActor
private final class UndoBox {
    private(set) var value = 0
    let history: UndoManager

    init(history: UndoManager) {
        self.history = history
    }

    func set(_ new: Int) {
        let old = value
        value = new
        history.registerUndo(withTarget: self) { box in
            MainActor.assumeIsolated { box.set(old) }
        }
        history.setActionName("Move Item")
    }
}
