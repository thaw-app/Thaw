//
//  MenuBarSearchPanelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Testing
@testable import Thaw

/// The search panel's rename, lookup and escape handling, on a panel that is never shown.
@MainActor
@Suite("Search panel", .serialized, .scratchDefaults)
struct MenuBarSearchPanelTests {
    private typealias World = LayoutEditorWorld

    private func panel(_ world: World) -> MenuBarSearchPanel {
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        return panel
    }

    @Test("A row's selection finds its item by window, or by tag when the row knew no window")
    func cachedItemLookup() {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = panel(world)

        #expect(panel.cachedItem(for: .item(alpha.tag, windowID: alpha.windowID))?.windowID == alpha.windowID)
        #expect(panel.cachedItem(for: .item(alpha.tag, windowID: nil))?.windowID == alpha.windowID)
        #expect(panel.cachedItem(for: .item(alpha.tag, windowID: 1)) == nil)
        #expect(panel.cachedItem(for: .header(.visible)) == nil)
        #expect(panel.cachedItem(for: .recentsHeader) == nil)
    }

    @Test("A panel that was never set up finds no items")
    func unsetPanelFindsNothing() {
        let alpha = World.item("Alpha")
        let panel = MenuBarSearchPanel()
        #expect(panel.cachedItem(for: .item(alpha.tag, windowID: alpha.windowID)) == nil)
        #expect(panel.selectedItem == nil)
        #expect(panel.canBecomeKey)
        #expect(panel.presentation == .inspector)
    }

    @Test("Edit Name starts a rename seeded with the item's custom name")
    func beginRenameSeedsDraft() throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "My Alpha"
        world.seat([alpha])
        let panel = panel(world)

        panel.beginRenamingSelection()
        #expect(panel.model.renameSession == nil, "nothing is highlighted yet")

        panel.model.selection = .item(alpha.tag, windowID: alpha.windowID)
        #expect(panel.selectedItem?.tag == alpha.tag)
        panel.beginRenamingSelection()
        let session = try #require(panel.model.renameSession)
        #expect(session.draft == "My Alpha")
        #expect(session.targets(alpha))
        #expect(!session.targets(World.item("Beta")))
    }

    @Test("Committing a rename saves the trimmed name, and an empty one removes it")
    func commitRenameSavesAndClears() {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = panel(world)

        panel.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "  Renamed  ")
        panel.commitRename()
        #expect(panel.model.renameSession == nil)
        #expect(alpha.customName == "Renamed")

        panel.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "   ")
        panel.commitRename()
        #expect(alpha.customName == nil)
    }

    @Test("Committing with no rename, or for an item that is gone, saves nothing")
    func commitRenameWithoutTarget() {
        let world = World()
        let alpha = World.item("Alpha")
        let panel = panel(world)

        panel.commitRename()
        panel.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "Lost")
        panel.commitRename()
        #expect(panel.model.renameSession == nil)
        #expect(alpha.customName == nil)
    }

    @Test("Escape backs out the rename, then the query, then closes the panel")
    func escapeBacksOutOneLayerAtATime() {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = panel(world)
        panel.model.searchText = "Al"
        panel.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "")
        world.appState.navigationState.isSearchPresented = true

        panel.cancelOperation(nil)
        #expect(panel.model.renameSession == nil)
        #expect(panel.model.searchText == "Al")

        panel.cancelOperation(nil)
        #expect(panel.model.searchText.isEmpty)
        #expect(world.appState.navigationState.isSearchPresented)

        panel.cancelOperation(nil)
        #expect(!world.appState.navigationState.isSearchPresented, "the last escape closes the panel")
    }

    @Test("Closing with Remember last search on keeps the query")
    func closeKeepsRememberedQuery() {
        let world = World()
        let panel = panel(world)
        Defaults.set(true, forKey: .rememberSearchQuery)
        panel.model.searchText = "Kept"
        panel.close()
        #expect(panel.model.searchText == "Kept")

        Defaults.set(false, forKey: .rememberSearchQuery)
        panel.close()
        #expect(panel.model.searchText.isEmpty)
    }

    @Test("Section shortcuts and the actions menu need a highlighted item")
    func itemActionsNeedASelection() {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = panel(world)

        panel.moveSelection(toDestinationAt: 1)
        panel.presentItemActions()
        #expect(world.appState.layoutFeedback.refusal == nil)

        // Out-of-range destinations and a move to the item's own section do nothing.
        panel.model.selection = .item(alpha.tag, windowID: alpha.windowID)
        panel.moveSelection(toDestinationAt: 7)
        panel.presentItemActions()
        #expect(world.appState.layoutFeedback.refusal == nil)
    }

    @Test("A section shortcut on an item macOS keeps in place explains the refusal")
    func protectedItemMoveIsExplained() throws {
        let world = World()
        let control = World.item(.visibleControlItem)
        world.seat([control])
        let panel = panel(world)
        panel.model.selection = .item(control.tag, windowID: control.windowID)
        // Checked first, so a backend that would allow it never starts a real move here.
        try #require(!MenuBarBackendProvider.current.canAssign(control, to: .hidden, experimentalSystemItemHiding: false))

        panel.moveSelection(toDestinationAt: 1)
        #expect(world.appState.layoutFeedback.refusal != nil)
    }

    @Test("The actions menu tracking keeps the panel up and closes it once it ends without key")
    func menuTracking() {
        let world = World()
        let panel = panel(world)
        world.appState.navigationState.isSearchPresented = true
        panel.menuWillOpen(NSMenu())
        panel.menuDidClose(NSMenu())
        #expect(!world.appState.navigationState.isSearchPresented, "a panel that is not key closes after the menu")
    }
}
