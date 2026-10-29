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
        #expect(titles.last == String(localized: "Reveal When Its Icon Changes"))

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
        #expect(!menu.items.contains { $0.title == String(localized: "Reveal When Its Icon Changes") })
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
}
