//
//  LayoutWindowLiveCheckTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import UniformTypeIdentifiers

/// What a hands-on pass of the Layout window found: renames that undo, keys, drops, ⌥-arrows and the filter.
@MainActor
@Suite("Layout window, as tried by hand", .serialized, .scratchDefaults)
struct LayoutWindowLiveCheckTests {
    private typealias World = LayoutEditorWorld
    private typealias Entry = LayoutBatchMoveSnapshot.Entry

    /// Items named as the list shows them: a test item otherwise reads as its owner, the test host.
    private static func named(_ names: [String]) -> [MenuBarItem] {
        let items = names.map { World.item($0) }
        Defaults.set(Dictionary(uniqueKeysWithValues: zip(items.map(\.uniqueIdentifier), names)), forKey: .menuBarItemCustomNames)
        return items
    }

    private static func entry(_ id: String, control: Bool = false) -> Entry {
        Entry(id: id, isControlItem: control, groupID: nil, assignableSections: Set(MenuBarSectionName.allCases), reordersInVisible: true)
    }

    // MARK: Renames

    @Test("Writing the custom names counts as a change, so the list and editor redraw on a rename or its undo")
    func namesRevision() {
        let world = World()
        let item = World.item("Widgets")
        world.seat([item], in: .visible)
        let shownName = LayoutItemList.sections(appState: world.appState, query: "").first?.rows.first?.name
        let undo = UndoManager()
        undo.groupsByEvent = false
        let before = MenuBarItemCustomNamesRevision.shared.value

        undo.beginUndoGrouping()
        LayoutEditUndo.rename(item, to: "Widgets Test", undoManager: undo)
        undo.endUndoGrouping()
        #expect(MenuBarItemCustomNamesRevision.shared.value != before)
        #expect(LayoutItemList.sections(appState: world.appState, query: "").first?.rows.first?.name == "Widgets Test")

        let afterRename = MenuBarItemCustomNamesRevision.shared.value
        undo.undo()
        #expect(MenuBarItemCustomNamesRevision.shared.value != afterRename, "the undo is a change too")
        #expect(item.customName == nil)
        #expect(LayoutItemList.sections(appState: world.appState, query: "").first?.rows.first?.name == shownName)
    }

    @Test("The editor's draft follows the stored name unless someone is typing a new one")
    func draftFollowsStoredName() {
        // The undo after Return: the field still shows the name it saved.
        #expect(LayoutItemNameDraft.following(draft: "Widgets Test", oldStored: "Widgets Test", newStored: "", isEditing: true) == "")
        #expect(LayoutItemNameDraft.following(draft: "Widgets Test", oldStored: "Widgets Test", newStored: "", isEditing: false) == "")
        #expect(LayoutItemNameDraft.following(draft: "Half typ", oldStored: "", newStored: "Other", isEditing: true) == "Half typ")
        #expect(LayoutItemNameDraft.following(draft: "Stale", oldStored: "", newStored: "Other", isEditing: false) == "Other")
    }

    @Test("Leaving the field saves only a draft that differs from the stored name")
    func commitOnlyChanges() {
        #expect(LayoutItemNameDraft.commit(draft: "", stored: "") == nil, "the undone rename isn't saved again")
        #expect(LayoutItemNameDraft.commit(draft: " Flux ", stored: "Flux") == nil)
        #expect(LayoutItemNameDraft.commit(draft: "Flux 2", stored: "Flux") == "Flux 2")
        #expect(LayoutItemNameDraft.commit(draft: "  ", stored: "Flux") == "", "an emptied field clears the name")
    }

    // MARK: Keys

    @Test("⌘Z and ⇧⌘Z reach the window anywhere in it, a field included")
    func undoKeys() {
        func action(_ characters: String, _ flags: NSEvent.ModifierFlags, editing: Bool = false) -> LayoutDashboardKeys.Action? {
            LayoutDashboardKeys.action(keyCode: .z, characters: characters, flags: flags, filterText: "", isEditingText: editing)
        }
        #expect(action("z", .command) == .undo(redo: false))
        #expect(action("z", .command, editing: true) == .undo(redo: false))
        #expect(action("Z", [.command, .shift]) == .undo(redo: true))
        #expect(action("z", []) == nil, "typing a z passes through")
    }

    @Test("Only a field editor counts as typing; SwiftUI's list responder doesn't, so Escape reaches the window")
    func editingText() {
        let fieldEditor = NSTextView()
        fieldEditor.isFieldEditor = true
        #expect(LayoutDashboardKeys.isEditingText(fieldEditor))
        #expect(!LayoutDashboardKeys.isEditingText(NSTextView()))
        #expect(!LayoutDashboardKeys.isEditingText(NSView()))
        #expect(!LayoutDashboardKeys.isEditingText(nil))
        #expect(LayoutDashboardKeys.action(keyCode: .escape, characters: "", flags: [], filterText: "fl", isEditingText: false) == .clearFilter)
    }

    @Test("The list maps Escape too, for a responder the window reads as typing")
    func listEscape() {
        #expect(LayoutItemListCommand.command(for: .escape, characters: "", modifiers: [])?.command == .escape)
        #expect(LayoutItemListCommand.command(for: .escape, characters: "", modifiers: .shift) == nil)
    }

    // MARK: Drops

    @Test("The rows' drag type is declared, so SwiftUI's drop targets accept it")
    func dragTypeDeclared() throws {
        let type = try #require(UTType(LayoutItemListDrop.type.identifier))
        #expect(type.isDeclared)
        #expect(type.conforms(to: .data))
        // Type identifiers ignore case, and UTType reports them lowercased.
        #expect(type.identifier.caseInsensitiveCompare(NSPasteboard.PasteboardType.layoutBarSelection.rawValue) == .orderedSame, "the bars and the Groups tab read the same type")
    }

    // MARK: ⌥-arrows

    @Test("⌥-arrows step over control items, which have no row")
    func nudgeSkipsControlItems() {
        let entries = [Self.entry("Sports"), Self.entry("Flux"), Self.entry("marker", control: true), Self.entry("WiFi")]
        #expect(LayoutItemListPlacement.nudge(["Flux"], in: entries, left: false) == .after("WiFi"))
        #expect(LayoutItemListPlacement.nudge(["WiFi"], in: entries, left: true) == .after("Sports"))
    }

    @Test("A step that would leave the order as it is isn't made, so it records no undo")
    func nudgeNoOp() {
        let entries = [Self.entry("Flux"), Self.entry("marker", control: true)]
        #expect(LayoutItemListPlacement.nudge(["Flux"], in: entries, left: false) == nil)
        #expect(LayoutItemListPlacement.order(["A", "B", "C"], moving: ["A"], to: .after("B")) == ["B", "A", "C"])
        #expect(LayoutItemListPlacement.order(["A", "B", "C"], moving: ["C"], to: .start) == ["C", "A", "B"])
        #expect(LayoutItemListPlacement.order(["A", "B", "C"], moving: ["A"], to: .end) == ["B", "C", "A"])
    }

    // MARK: Filter

    @Test("A short query matches its letters in order: \"fl\" finds Flux and Floe, not Clock or Bluetooth")
    func shortQueryIsStrict() {
        let items = Self.named(["Flux", "WiFi", "Floe", "Clock", "Little Snitch Agent", "Bluetooth"])
        let sections = LayoutItemList.sections(from: [.visible: items], order: [.visible], query: "fl")
        #expect(sections.flatMap(\.rows).map(\.name).sorted() == ["Floe", "Flux"])
    }

    @Test("In-order matching ignores case and accents, and longer queries keep typo tolerance")
    func inOrder() {
        #expect(LayoutItemList.contains("fl", inOrderIn: "Floe"))
        #expect(LayoutItemList.contains("FX", inOrderIn: "flux"))
        #expect(LayoutItemList.contains("ce", inOrderIn: "Café"))
        #expect(!LayoutItemList.contains("fl", inOrderIn: "Little Snitch Agent"))
        #expect(!LayoutItemList.contains("lf", inOrderIn: "Flux"))
        let items = Self.named(["Bluetooth", "Battery"])
        let typo = LayoutItemList.sections(from: [.visible: items], order: [.visible], query: "bluetoth")
        #expect(typo.flatMap(\.rows).map(\.name).contains("Bluetooth"), "a four-letter-plus query still forgives a typo")
    }

    // MARK: Look

    @Test("A Thaw module's item reads as part of Thaw")
    func thawModule() {
        #expect(LayoutItemAppDetails.isThawModule("com.stonerl.Thaw.module.widgets", thawIdentifier: "com.stonerl.Thaw"))
        #expect(!LayoutItemAppDetails.isThawModule("com.stonerl.Thaw", thawIdentifier: "com.stonerl.Thaw"))
        #expect(!LayoutItemAppDetails.isThawModule("com.stonerl.ThawOther", thawIdentifier: "com.stonerl.Thaw"))
    }
}
