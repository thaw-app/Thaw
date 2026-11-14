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
import ThawUI

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

        #expect(panel.cachedItem(for: MenuBarSearchModel.ItemID(alpha))?.windowID == alpha.windowID)
        #expect(panel.cachedItem(for: MenuBarSearchModel.ItemID(tag: alpha.tag, windowID: nil))?.windowID == alpha.windowID)
        #expect(panel.cachedItem(for: MenuBarSearchModel.ItemID(tag: alpha.tag, windowID: 1)) == nil)
    }

    @Test("A panel that was never set up finds no items")
    func unsetPanelFindsNothing() {
        let alpha = World.item("Alpha")
        let panel = MenuBarSearchPanel()
        #expect(panel.cachedItem(for: MenuBarSearchModel.ItemID(alpha)) == nil)
        #expect(panel.selectedItem == nil)
        #expect(panel.canBecomeKey)
        #expect(panel.presentation == .extended)
    }

    @Test("Rename… starts a rename seeded with the item's custom name")
    func beginRenameSeedsDraft() throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "My Alpha"
        world.seat([alpha])
        let panel = panel(world)

        panel.beginRenamingSelection()
        #expect(panel.model.renameSession == nil, "nothing is highlighted yet")

        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        #expect(panel.selectedItem?.tag == alpha.tag)
        panel.beginRenamingSelection()
        let session = try #require(panel.model.renameSession)
        #expect(session.draft == "My Alpha")
        #expect(session.targets(alpha))
        #expect(!session.targets(World.item("Beta")))
    }

    @Test("Pressing Command-E again preserves the rename draft", arguments: ["", "My Alpha"])
    func repeatedRenameShortcutPreservesDraft(savedName: String) throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = savedName.isEmpty ? nil : savedName
        world.seat([alpha])
        let panel = panel(world)
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: UInt16(KeyCode.e.rawValue)
        ))
        #expect(panel.handleKeyDown(event) == nil)
        #expect(try #require(panel.model.renameSession).draft == savedName)

        panel.model.renameSession?.draft = "New name in progress"
        _ = panel.handleKeyDown(event)
        let session = try #require(panel.model.renameSession)
        #expect(session.draft == "New name in progress")
        #expect(session.targets(alpha))
        #expect((alpha.customName ?? "") == savedName)

        panel.commitRename()
        #expect(alpha.customName == "New name in progress")
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

    /// Layout renames and profile changes update defaults without necessarily replacing the item cache.
    @Test("Search refresh sees custom names changed elsewhere", arguments: [false, true])
    func refreshSeesExternalNameChange(cleared: Bool) throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "Work meetings"
        world.seat([alpha])
        let panel = panel(world)
        let inventory = world.appState.itemManager.itemCache
        panel.model.refresh(from: inventory)
        #expect(panel.model.candidates.first?.displayName == "Work meetings")

        alpha.customName = cleared ? nil : "Music controls"
        let expectedName = MenuBarItemDisplayName.displayName(for: alpha)
        panel.model.searchText = expectedName
        panel.model.refresh(from: inventory)

        #expect(panel.model.candidates.first?.displayName == expectedName)
        let result = try #require(panel.model.results.first)
        #expect(result.id == MenuBarSearchModel.ItemID(alpha))
        #expect(result.ownerName == MenuBarItemDisplayName.subtitle(for: alpha))
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
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        panel.moveSelection(toDestinationAt: 7)
        panel.presentItemActions()
        #expect(world.appState.layoutFeedback.refusal == nil)
    }

    /// Global events and another window's keys must not act on the search selection.
    @Test("Search command shortcuts only handle their own window", arguments: [false, true])
    func commandShortcutsStayInTheirWindow(otherWindow: Bool) throws {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = panel(world)
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }

        func renameKey(windowNumber: Int) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: windowNumber,
                context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: UInt16(KeyCode.e.rawValue)
            ))
        }

        let unrelated = try renameKey(windowNumber: otherWindow ? other.windowNumber : 0)
        #expect(unrelated.window !== panel)
        #expect(MenuBarSearchPanel.monitoredKey(unrelated, panel: panel) === unrelated)
        #expect(panel.model.renameSession == nil)

        let own = try renameKey(windowNumber: panel.windowNumber)
        #expect(MenuBarSearchPanel.monitoredKey(own, panel: panel) == nil)
        #expect(panel.model.renameSession?.targets(alpha) == true)
    }

    @Test("Collapsed to the field alone, Return and the item shortcuts pass through")
    func collapsedFacesDontActOnTheHiddenSelection() throws {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = panel(world)
        panel.presentation = .compact
        panel.model.results = [MenuBarSearchResult(item: alpha, ownerName: nil, section: nil)]
        panel.model.selectFirstRow()

        func key(_ code: KeyCode, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: UInt16(code.rawValue)
            ))
        }

        // Collapsed to just the field, no row shows, so keys that act on the
        // hidden first result pass through instead.
        #expect(!panel.showsAResultRow)
        #expect(try panel.handleKeyDown(key(.returnKey)) != nil)
        #expect(try panel.handleKeyDown(key(.e, .command)) != nil)
        #expect(try panel.handleKeyDown(key(.two, .command)) != nil)
        #expect(panel.model.renameSession == nil)

        // Typed, the list shows and the same keys act on the highlighted row.
        panel.model.searchText = "al"
        #expect(panel.showsAResultRow)
        #expect(try panel.handleKeyDown(key(.e, .command)) == nil)
        #expect(panel.model.renameSession != nil)
    }

    @Test("Collapsed to the field alone, the arrows and Tab leave the hidden selection where it is")
    func collapsedFacesDontMoveTheHiddenSelection() throws {
        let world = World()
        let alpha = World.item("Alpha"), beta = World.item("Alpha Beta")
        world.seat([alpha, beta])
        let panel = panel(world)
        panel.presentation = .compact
        panel.model.results = [alpha, beta].map { MenuBarSearchResult(item: $0, ownerName: nil, section: nil) }
        panel.model.selectFirstRow()
        let first = panel.model.selection

        func key(_ code: KeyCode) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code.rawValue)
            ))
        }

        // No row shows, so the arrows pass through to move the field's text cursor.
        #expect(!panel.showsAResultRow)
        #expect(try panel.handleKeyDown(key(.downArrow)) != nil)
        #expect(panel.model.selection == first)
        // With no section to jump to, Tab passes through to move the keyboard focus.
        #expect(try panel.handleKeyDown(key(.tab)) != nil)
        #expect(panel.model.selection == first)

        // Typed, the list shows and Down moves the highlight.
        panel.model.searchText = "al"
        #expect(panel.showsAResultRow)
        #expect(try panel.handleKeyDown(key(.downArrow)) == nil)
        #expect(panel.model.selection != first)
    }

    @Test("Tab jumps between sections, and passes through when there is only one")
    func tabJumpsOnlyBetweenSections() throws {
        let world = World()
        let alpha = World.item("Alpha"), beta = World.item("Beta")
        world.seat([alpha, beta])
        let panel = panel(world)

        func tab() throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(KeyCode.tab.rawValue)
            ))
        }

        panel.model.results = [
            MenuBarSearchResult(item: alpha, ownerName: nil, section: "Visible"),
            MenuBarSearchResult(item: beta, ownerName: nil, section: "Hidden"),
        ]
        panel.model.selectFirstRow()
        #expect(try panel.handleKeyDown(tab()) == nil)
        #expect(panel.model.selection == MenuBarSearchModel.ItemID(beta))

        panel.model.results = [alpha, beta].map { MenuBarSearchResult(item: $0, ownerName: nil, section: "Visible") }
        #expect(try panel.handleKeyDown(tab()) != nil)
        #expect(panel.model.selection == MenuBarSearchModel.ItemID(beta))

        // The key monitor hands on the handler's answer: a taken Tab stays taken.
        panel.model.results[0] = MenuBarSearchResult(item: alpha, ownerName: nil, section: "Hidden")
        #expect(try MenuBarSearchPanel.monitoredKey(tab(), panel: panel) == nil)
        let event = try tab()
        #expect(MenuBarSearchPanel.monitoredKey(event, panel: nil) === event)
    }

    @Test("A rename ends when its row leaves the list")
    func renameEndsWithItsRow() {
        let world = World()
        let alpha = World.item("Clock"), beta = World.item("Battery")
        world.seat([alpha, beta])
        let panel = panel(world)
        let inventory = DisplayedItemInventory.cache(appState: world.appState)

        panel.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "New")
        panel.model.searchText = "clock"
        panel.model.refresh(from: inventory)
        #expect(panel.model.renameSession != nil, "the row is still listed")

        panel.model.searchText = "battery"
        panel.model.refresh(from: inventory)
        #expect(panel.model.renameSession == nil)
    }

    @Test("A section shortcut on an item macOS keeps in place explains the refusal")
    func protectedItemMoveIsExplained() throws {
        let world = World()
        let control = World.item(.visibleControlItem)
        world.seat([control])
        let panel = panel(world)
        panel.model.selection = MenuBarSearchModel.ItemID(control)
        // Checked first, so a backend that would allow it never starts a real move here.
        try #require(!MenuBarBackendProvider.current.canAssign(control, to: .hidden, experimentalSystemItemHiding: false))

        panel.moveSelection(toDestinationAt: 1)
        #expect(world.appState.layoutFeedback.refusal != nil)
    }

    @Test("A rename drops the inventory ranked by the old name, and a section shortcut is attempted")
    func renameAndMove() throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "My Alpha"
        let control = World.item(.visibleControlItem)
        world.seat([alpha, control])
        let panel = panel(world)

        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        panel.beginRenamingSelection()
        let session = try #require(panel.model.renameSession)
        #expect(session.draft == "My Alpha")
        panel.model.renameSession?.draft = "Renamed"
        panel.model.candidates = [
            PaletteCandidate(item: alpha, displayName: "My Alpha", ownerName: "", identityKey: alpha.uniqueIdentifier),
        ]
        panel.commitRename()
        #expect(alpha.customName == "Renamed")
        #expect(!panel.model.candidates.contains { $0.displayName == "My Alpha" }, "the inventory is rebuilt with the new name")

        // A refusal shows the move was attempted rather than ignored.
        try #require(!MenuBarBackendProvider.current.canAssign(control, to: .hidden, experimentalSystemItemHiding: false))
        panel.model.selection = MenuBarSearchModel.ItemID(control)
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
