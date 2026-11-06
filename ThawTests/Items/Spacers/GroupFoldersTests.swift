//
//  GroupFoldersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Which groups are folders, how each folder icon looks and what it is called, read from and
/// written to a throwaway suite. No folder icon is put in the menu bar.
@MainActor
@Suite("Group folders", .serialized, .scratchDefaults)
struct GroupFoldersTests {
    private static let foldersKey = "MenuBarItemGroupManager.folderGroups"
    private static let stylesKey = "MenuBarItemGroupManager.folderStyles"

    @Test("Stored folder IDs load, and malformed ones are skipped")
    func loadsFolders() {
        let folder = UUID()
        Defaults.store.set([folder.uuidString, "not-a-uuid"], forKey: Self.foldersKey)
        let folders = GroupFolders()
        #expect(folders.isFolder(.user(folder)))
        #expect(!folders.isFolder(.user(UUID())))
    }

    @Test("A folder's style is saved with its colour and read back by a new instance")
    func stylesRoundTrip() throws {
        let folder = UUID()
        Defaults.store.set([folder.uuidString], forKey: Self.foldersKey)
        let folders = GroupFolders()
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        folders.setStyle(GroupFolders.Style(symbol: "star", color: red), for: folder)

        let stored = try #require(Defaults.store.dictionary(forKey: Self.stylesKey) as? [String: [String: String]])
        #expect(stored[folder.uuidString] == ["symbol": "star", "color": "#FF0000"])

        let reloaded = GroupFolders().style(for: folder)
        #expect(reloaded.symbol == "star")
        #expect(reloaded.color?.usingColorSpace(.sRGB)?.redComponent == 1)
        #expect(reloaded.color?.usingColorSpace(.sRGB)?.greenComponent == 0)
    }

    @Test("The default style is not stored, and a style for a group that isn't a folder isn't either")
    func defaultsNotStored() throws {
        let folder = UUID()
        let plainGroup = UUID()
        Defaults.store.set([folder.uuidString], forKey: Self.foldersKey)
        let folders = GroupFolders()

        folders.setStyle(GroupFolders.Style(symbol: "bolt"), for: plainGroup)
        folders.setStyle(GroupFolders.Style(), for: folder)

        let stored = try #require(Defaults.store.dictionary(forKey: Self.stylesKey) as? [String: [String: String]])
        #expect(stored.isEmpty)
        #expect(folders.style(for: plainGroup).symbol == "bolt", "kept in memory for the open editor")
        #expect(folders.style(for: folder) == GroupFolders.Style())
    }

    @Test("Stored styles with a bad colour or a missing symbol fall back per field")
    func loadsPartialStyles() {
        let folder = UUID()
        Defaults.store.set([folder.uuidString], forKey: Self.foldersKey)
        Defaults.store.set([
            folder.uuidString: ["color": "#12"],
            "not-a-uuid": ["symbol": "star"],
        ], forKey: Self.stylesKey)

        let style = GroupFolders().style(for: folder)
        #expect(style.symbol == GroupFolders.Style.defaultSymbol)
        #expect(style.color == nil)
    }

    @Test("A group made automatically from an app's items is never a folder")
    func automaticGroups() {
        let folders = GroupFolders()
        #expect(!folders.isFolder(.automatic(.string("com.example.app"))))
    }

    @Test("A folder icon's label is looked up by its autosave name, for Thaw's own items only")
    func labels() {
        let name = GroupFolders.autosavePrefix + UUID().uuidString
        Defaults.store.set([name: "Chat apps"], forKey: GroupFolders.labelsKey)

        #expect(GroupFolders.label(for: MenuBarItemTag(namespace: .thaw, title: name)) == "Chat apps")
        #expect(GroupFolders.label(for: MenuBarItemTag(namespace: .thaw, title: "Thaw.ControlItem.Visible")) == nil)
        #expect(GroupFolders.label(for: MenuBarItemTag(namespace: .string("com.example.app"), title: name)) == nil)
        #expect(GroupFolders.label(for: MenuBarItemTag(namespace: .thaw, title: GroupFolders.autosavePrefix + "unknown")) == nil)
    }

    @Test("The symbol list starts with the folder shapes and has no duplicates")
    func symbols() {
        #expect(GroupFolders.Style.symbols.first == GroupFolders.Style.defaultSymbol)
        #expect(Set(GroupFolders.Style.symbols).count == GroupFolders.Style.symbols.count)
        #expect(GroupFolders.Style.symbols.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
    }

    @Test("Without setup, a folder owns no window and the pointer is never on one")
    func beforeSetup() {
        let folders = GroupFolders()
        #expect(!folders.ownsWindowID(1))
        #expect(!folders.iconContainsPointer())
    }

    @Test("Setup drops folders whose group is gone, with their styles and icon labels", .timeLimit(.minutes(1)))
    func setupPrunesStaleFolders() async throws {
        let stale = UUID()
        Defaults.store.set([stale.uuidString], forKey: Self.foldersKey)
        Defaults.store.set([stale.uuidString: ["symbol": "star"]], forKey: Self.stylesKey)
        Defaults.store.set([GroupFolders.autosavePrefix + stale.uuidString: "Old"], forKey: GroupFolders.labelsKey)
        let folders = GroupFolders()
        try #require(folders.isFolder(.user(stale)))

        // GroupFolders holds the app state weakly, so the test keeps it alive.
        let appState = AppState()
        folders.performSetup(with: appState)
        await waitUntil {
            !folders.isFolder(.user(stale))
        } tracking: {
            _ = folders.isFolder(.user(stale))
        }

        #expect(Defaults.store.stringArray(forKey: Self.foldersKey) == [])
        #expect((Defaults.store.dictionary(forKey: Self.stylesKey) as? [String: [String: String]])?.isEmpty == true)
        #expect((Defaults.store.dictionary(forKey: GroupFolders.labelsKey) as? [String: String])?.isEmpty == true)
        withExtendedLifetime(appState) {}
    }

    @Test("Making a group that no longer exists a folder leaves no folder behind", .timeLimit(.minutes(1)))
    func folderForMissingGroup() {
        let folders = GroupFolders()
        let appState = AppState()
        folders.performSetup(with: appState)
        let missing = UUID()

        folders.setFolder(true, for: .user(missing), members: [])

        #expect(!folders.isFolder(.user(missing)))
        #expect(Defaults.store.stringArray(forKey: Self.foldersKey) == [])
        withExtendedLifetime(appState) {}
    }

    @Test("A Thaw item's bar bounds are found by autosave name, ignoring other apps' items of that name")
    func barBounds() {
        let world = LayoutEditorWorld()
        let name = GroupFolders.autosavePrefix + UUID().uuidString
        let foreign = LayoutEditorWorld.item(MenuBarItemTag(namespace: .string("com.example.app"), title: name))
        let own = LayoutEditorWorld.item(MenuBarItemTag(namespace: .thaw, title: name))
        world.seat([foreign, own])

        #expect(world.appState.itemManager.barBounds(ofThawItemNamed: name) == own.bounds)
        #expect(world.appState.itemManager.barBounds(ofThawItemNamed: GroupFolders.autosavePrefix + "missing") == nil)
    }

    @Test("A folder is called by its group's name, or else by up to three of its members' names", .timeLimit(.minutes(1)))
    func folderNames() throws {
        let items = ["Alpha", "Beta", "Gamma", "Delta"].map(LayoutEditorWorld.item)
        Defaults.set(Dictionary(uniqueKeysWithValues: items.map { ($0.uniqueIdentifier, $0.title ?? "") }), forKey: .menuBarItemCustomNames)
        let world = LayoutEditorWorld()
        world.seat(items)
        let manager = world.appState.itemGroupManager
        let named = try #require(manager.createGroup(name: "Chat apps", items: Array(items.prefix(2))))
        let nameless = try #require(manager.createGroup(name: nil, items: items))
        let folders = GroupFolders()
        folders.performSetup(with: world.appState)

        #expect(folders.folderName(for: named) == "Chat apps")
        #expect(folders.folderName(for: nameless) == ListFormatter.localizedString(byJoining: ["Alpha", "Beta", "Gamma"]))

        world.seat([])
        #expect(folders.folderName(for: nameless) == String(localized: "Folder"), "no member is on the bar to name it after")
    }
}
