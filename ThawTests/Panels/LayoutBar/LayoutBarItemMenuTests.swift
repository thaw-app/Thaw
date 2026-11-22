//
//  LayoutBarItemMenuTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw
import ThawUI

/// The layout editor's right-click menu, built and read without running its actions.
@MainActor
@Suite("Layout bar item menu", .serialized, .scratchDefaults)
struct LayoutBarItemMenuTests {
    private typealias World = LayoutEditorWorld

    private static func pair() -> [MenuBarItem] {
        ["One", "Two"].map {
            World.item(MenuBarItemTag(namespace: .string("com.example.Pair"), title: $0, instanceIndex: 0))
        }
    }

    private func titles(_ menu: NSMenu?) -> [String] {
        menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
    }

    @Test("A loose item offers its own actions, grouping with another loose item and the reveal switch")
    func looseItem() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        var renamed = false
        let built = LayoutBarItemMenu.menu(
            subject: .item(alpha),
            section: .visible,
            orderedItems: [alpha, beta],
            appState: world.appState,
            onRename: { renamed = true }
        )
        let menu = try #require(built)
        let titles = titles(menu)
        #expect(titles.first == String(localized: "Rename…"))
        #expect(titles.contains(String(localized: "Move to")))
        #expect(titles.contains(String(localized: "Choose Icon…")))
        #expect(titles.contains(String(localized: "Set Shortcut…")))
        #expect(titles.last == String(localized: "Show When Its Icon Changes"))

        let groupWith = try #require(menu.items.first { $0.title == String(localized: "Group With") })
        #expect(groupWith.submenu?.items.map(\.title) == [beta.displayName])

        let rename = try #require(menu.items.first as? ClosureMenuItem)
        _ = rename.target?.perform(rename.action)
        #expect(renamed)
    }

    @Test("The reveal switch shows its stored state")
    func revealSwitchState() throws {
        let world = World()
        let alpha = World.item("Alpha")
        MenuBarItemAlertReveals.setEnabled(true, for: alpha.tag.tagIdentifier)
        let menu = try #require(LayoutBarItemMenu.menu(subject: .item(alpha), section: .visible, orderedItems: [alpha], appState: world.appState))
        #expect(menu.items.last?.state == .on)
        #expect(!menu.items.contains { $0.title == String(localized: "Rename…") }, "no rename without a handler")
        #expect(!menu.items.contains { $0.title == String(localized: "Group With") }, "no partner, no grouping")
    }

    @Test("A move entry numbers each destination and checks the item's section")
    func moveEntry() throws {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha], in: .visible)
        let entry = LayoutBarItemMenu.moveEntry(for: alpha, appState: world.appState)
        let submenu = try #require(entry.submenu)
        #expect(submenu.items.first?.keyEquivalent == "1")
        #expect(submenu.items.allSatisfy { $0.keyEquivalentModifierMask == .command })
        let current = world.appState.menuBarManager.sectionController.section(for: alpha)
        #expect(submenu.items.filter { $0.state == .on }.map(\.title) == [current.localizedName])
    }

    @Test("A control item cannot be grouped and says so")
    func controlItem() throws {
        let world = World()
        let control = World.item(.visibleControlItem)
        let menu = try #require(LayoutBarItemMenu.menu(subject: .item(control), section: .visible, orderedItems: [control], appState: world.appState))
        let explanation = try #require(menu.items.first)
        #expect(!explanation.isEnabled)
        // A menu enables every item it can on opening, unless the item itself says no.
        _ = NSApplication.shared
        menu.update()
        #expect(!explanation.isEnabled)
        #expect(!menu.items.contains { $0.title == String(localized: "Move to") })
    }

    @Test("A grouped item offers its group's entries and leaving the group")
    func groupedItem() throws {
        let world = World()
        let pair = Self.pair()
        let groups = world.appState.itemGroupManager.resolvedGroups(for: pair)
        try #require(groups.count == 1, "items of one app form an automatic group")
        let name = world.appState.itemGroupManager.displayName(for: groups[0], in: pair)

        let menu = try #require(LayoutBarItemMenu.menu(subject: .item(pair[0]), section: .visible, orderedItems: pair, appState: world.appState))
        let titles = titles(menu)
        #expect(titles.contains(String(localized: "Ungroup “\(name)”")))
        #expect(titles.contains(String(localized: "Remove “\(pair[0].displayName)” from Group")))
        #expect(!menu.items.contains { $0.title == String(localized: "Group With") })
    }

    @Test("A group's own menu offers collapse, folder and ungroup")
    func groupSubject() throws {
        let world = World()
        let pair = Self.pair()
        let group = try #require(world.appState.itemGroupManager.resolvedGroups(for: pair).first)
        let menu = try #require(LayoutBarItemMenu.menu(subject: .group(group), section: .visible, orderedItems: pair, appState: world.appState))
        #expect(menu.items.count == 3)
        #expect(!menu.items.contains { $0.title == String(localized: "Show When Its Icon Changes") })
    }

    @Test("A loose item beside a group can be added to it")
    func addToGroup() throws {
        let world = World()
        let pair = Self.pair()
        let alpha = World.item("Alpha")
        let ordered = pair + [alpha]
        let menu = try #require(LayoutBarItemMenu.menu(subject: .item(alpha), section: .visible, orderedItems: ordered, appState: world.appState))
        let addTo = try #require(menu.items.first { $0.title == String(localized: "Add to Group") })
        #expect(addTo.submenu?.items.count == 1)
    }

    @Test("Choosing the reveal switch flips the stored state each time")
    func revealSwitchToggles() throws {
        let world = World()
        let alpha = World.item("Alpha")
        func choose() throws {
            let menu = try #require(LayoutBarItemMenu.menu(subject: .item(alpha), section: .visible, orderedItems: [alpha], appState: world.appState))
            let entry = try #require(menu.items.last as? ClosureMenuItem)
            _ = entry.target?.perform(entry.action)
        }
        try choose()
        #expect(MenuBarItemAlertReveals.contains(alpha.tag.tagIdentifier))
        try choose()
        #expect(!MenuBarItemAlertReveals.contains(alpha.tag.tagIdentifier))
    }
}

/// The layout editor menu's group entries, chosen and read back through the group manager.
/// Only entries that change stored groups run here; none of them moves an item.
@MainActor
@Suite("Layout bar item menu actions", .serialized, .scratchDefaults)
struct LayoutBarItemMenuActionTests {
    private typealias World = LayoutEditorWorld

    private static func pair() -> [MenuBarItem] {
        ["One", "Two"].map {
            World.item(MenuBarItemTag(namespace: .string("com.example.Pair"), title: $0, instanceIndex: 0))
        }
    }

    private func menu(_ subject: LayoutBarItemMenu.Subject, _ ordered: [MenuBarItem], _ world: World) throws -> NSMenu {
        try #require(LayoutBarItemMenu.menu(subject: subject, section: .visible, orderedItems: ordered, appState: world.appState))
    }

    private func choose(_ entry: NSMenuItem?) throws {
        let entry = try #require(entry as? ClosureMenuItem)
        _ = entry.target?.perform(entry.action)
    }

    private func entry(_ menu: NSMenu, titled title: String) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }

    @Test("Choosing a partner under Group With stores a group of the two")
    func groupWithPartner() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let ordered = [alpha, beta]
        let built = try menu(.item(alpha), ordered, world)

        try choose(entry(built, titled: String(localized: "Group With"))?.submenu?.items.first)

        let groups = world.appState.itemGroupManager.resolvedGroups(for: ordered)
        try #require(groups.count == 1)
        guard case .user = groups[0].origin else {
            Issue.record("a chosen pairing is stored as a user group")
            return
        }
        #expect(groups[0].memberIndices == [0, 1])
    }

    @Test("Adding to an app's automatic group stores it with the new member")
    func addToAutomaticGroup() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let ordered = Self.pair() + [alpha]
        let built = try menu(.item(alpha), ordered, world)

        try choose(entry(built, titled: String(localized: "Add to Group"))?.submenu?.items.first)

        let group = try #require(world.appState.itemGroupManager.resolvedGroup(containing: alpha, in: ordered))
        guard case .user = group.origin else {
            Issue.record("the automatic cluster is stored before a foreign member joins")
            return
        }
        #expect(group.count == 3)
    }

    @Test("Adding to a stored group adds the item to that same group")
    func addToUserGroup() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let gamma = World.item("Gamma")
        let ordered = [alpha, beta, gamma]
        let created = try #require(world.appState.itemGroupManager.createGroup(name: "Mine", items: [alpha, beta]))
        let built = try menu(.item(gamma), ordered, world)

        let addTo = try #require(entry(built, titled: String(localized: "Add to Group")))
        #expect(addTo.submenu?.items.map(\.title) == ["Mine"])
        try choose(addTo.submenu?.items.first)

        let stored = try #require(world.appState.itemGroupManager.groupSet.groups.first { $0.id == created.id })
        #expect(stored.memberIdentifiers.count == 3)
        #expect(world.appState.itemGroupManager.groupSet.groups.count == 1)
    }

    @Test("Removing a member leaves the rest of its group together")
    func removeMember() throws {
        let world = World()
        let items = ["Alpha", "Beta", "Gamma"].map(World.item)
        try #require(world.appState.itemGroupManager.createGroup(name: "Trio", items: items) != nil)
        let built = try menu(.item(items[0]), items, world)

        try choose(entry(built, titled: String(localized: "Remove “\(items[0].displayName)” from Group")))

        let manager = world.appState.itemGroupManager
        #expect(manager.resolvedGroup(containing: items[0], in: items) == nil)
        #expect(manager.resolvedGroup(containing: items[1], in: items)?.count == 2)
    }

    @Test("Collapse folds a group and the rebuilt menu offers to expand it")
    func collapseAndExpand() throws {
        let world = World()
        let items = ["Alpha", "Beta"].map(World.item)
        try #require(world.appState.itemGroupManager.createGroup(name: "Duo", items: items) != nil)
        let manager = world.appState.itemGroupManager
        let group = try #require(manager.resolvedGroups(for: items).first)
        try #require(!group.isCollapsed)

        try choose(entry(menu(.group(group), items, world), titled: String(localized: "Collapse “Duo”")))

        let collapsed = try #require(manager.resolvedGroups(for: items).first)
        #expect(collapsed.isCollapsed)
        let rebuilt = try menu(.group(collapsed), items, world)
        #expect(entry(rebuilt, titled: String(localized: "Expand “Duo”")) != nil)
        #expect(entry(rebuilt, titled: String(localized: "Show “Duo” as a Folder")) != nil)
    }

    @Test("Ungroup removes a stored group")
    func ungroupUserGroup() throws {
        let world = World()
        let items = ["Alpha", "Beta"].map(World.item)
        try #require(world.appState.itemGroupManager.createGroup(name: "Duo", items: items) != nil)
        let group = try #require(world.appState.itemGroupManager.resolvedGroups(for: items).first)

        try choose(entry(menu(.group(group), items, world), titled: String(localized: "Ungroup “Duo”")))

        #expect(world.appState.itemGroupManager.groupSet.groups.isEmpty)
        #expect(world.appState.itemGroupManager.resolvedGroups(for: items).isEmpty)
    }

    @Test("Ungrouping an app's automatic group keeps it from forming again")
    func ungroupAutomaticGroup() throws {
        let world = World()
        let pair = Self.pair()
        let group = try #require(world.appState.itemGroupManager.resolvedGroups(for: pair).first)
        let name = world.appState.itemGroupManager.displayName(for: group, in: pair)

        try choose(entry(menu(.item(pair[1]), pair, world), titled: String(localized: "Ungroup “\(name)”")))

        #expect(world.appState.itemGroupManager.resolvedGroups(for: pair).isEmpty)
    }
}
