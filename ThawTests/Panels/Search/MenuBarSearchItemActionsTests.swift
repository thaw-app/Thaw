//
//  MenuBarSearchItemActionsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// The organising verbs the search panel offers, built without running any move.
@MainActor
@Suite("Search item actions", .serialized, .scratchDefaults)
struct MenuBarSearchItemActionsTests {
    private typealias World = LayoutEditorWorld

    @Test("A section that is switched off keeps its number but is no destination")
    func destinationsKeepTheirNumbers() {
        let world = World()
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: world.appState)
        #expect(destinations.count == MenuBarSection.Name.allCases.count)
        for (index, name) in MenuBarSection.Name.allCases.enumerated() {
            let isEnabled = world.appState.menuBarManager.section(withName: name)?.isEnabled ?? true
            #expect(destinations[index] == (isEnabled ? name : nil))
        }
        #expect(destinations.prefix(2) == [.visible, .hidden])
    }

    @Test("An item's menu offers a move to each section, checks its own, and ends with the settings entry")
    func menuForAnItem() throws {
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        var openedSettings = false
        let menu = MenuBarSearchItemActions.menu(for: alpha, appState: world.appState) {
            openedSettings = true
        }

        let moveEntry = try #require(menu.items.first { $0.title == String(localized: "Move to") })
        let destinations = try #require(moveEntry.submenu?.items)
        let names = MenuBarSearchItemActions.moveDestinations(appState: world.appState)
        #expect(destinations.map(\.title) == names.compactMap(\.self).map(\.localizedName))
        #expect(destinations.map(\.keyEquivalent) == names.enumerated().compactMap { $0.element == nil ? nil : String($0.offset + 1) })
        let current = world.appState.menuBarManager.sectionController.section(for: alpha)
        #expect(destinations.filter { $0.state == .on }.map(\.title) == [current.localizedName])

        let settings = try #require(menu.items.last as? ClosureMenuItem)
        #expect(settings.keyEquivalent == "l")
        #expect(settings.keyEquivalentModifierMask == .command)
        _ = settings.target?.perform(settings.action)
        #expect(openedSettings)
        #expect(menu.items.contains { $0.title == String(localized: "Reveal When Its Icon Changes") })
    }

    @Test("A control item's menu has no item entries, only the reveal and settings entries")
    func menuForAControlItem() {
        let world = World()
        let control = World.item(.visibleControlItem)
        world.seat([control])
        let menu = MenuBarSearchItemActions.menu(for: control, appState: world.appState) {}
        #expect(!menu.items.contains { $0.title == String(localized: "Move to") })
        #expect(menu.items.last?.title == String(localized: "Open Layout Settings…"))
    }

    @Test("A refused move posts the message for an item that stays put")
    func refusalIsPosted() throws {
        let world = World()
        let control = World.item(.visibleControlItem)
        MenuBarSearchItemActions.postAssignmentRefusal(
            for: control,
            to: .hidden,
            experimentalSystemItemHiding: true,
            appState: world.appState
        )
        let refusal = try #require(world.appState.layoutFeedback.refusal)
        let expected = LayoutBarFeedbackCenter.itemCannotMove(itemName: control.displayName, section: .hidden)
        #expect(refusal.title == expected.title)
        #expect(refusal.message == expected.message)
    }

    @Test("Moving an item macOS keeps in place explains itself instead of moving")
    func protectedMoveIsRefused() throws {
        let world = World()
        let control = World.item(.visibleControlItem)
        world.seat([control])
        // Checked first, so a backend that would allow it never starts a real move here.
        try #require(!MenuBarBackendProvider.current.canAssign(control, to: .alwaysHidden, experimentalSystemItemHiding: false))
        MenuBarSearchItemActions.move(control, to: .alwaysHidden, appState: world.appState)
        let refusal = try #require(world.appState.layoutFeedback.refusal)
        #expect(refusal.message == LayoutBarFeedbackCenter.itemCannotMove(itemName: control.displayName, section: .alwaysHidden).message)
    }

    @Test("A batch with nothing the section can take does nothing")
    func emptyBatchDoesNothing() {
        let world = World()
        let control = World.item(.visibleControlItem)
        MenuBarSearchItemActions.move([control], to: .alwaysHidden, appState: world.appState)
        MenuBarSearchItemActions.move([], to: .hidden, appState: world.appState)
        #expect(world.appState.layoutFeedback.refusal == nil)
    }

    @Test("An ungrouped item's group name falls back to its own name")
    func groupNameFallback() {
        let world = World()
        let alpha = World.item("Alpha")
        #expect(MenuBarSearchItemActions.groupDisplayName(for: [alpha], in: [alpha], appState: world.appState) == alpha.displayName)
        #expect(MenuBarSearchItemActions.groupDisplayName(for: [], in: [], appState: world.appState).isEmpty)
    }

    @Test("A refusal that system item hiding would lift names that setting")
    func refusalNamesTheSetting() throws {
        let world = World()
        let clock = World.item(.clock)
        try #require(!MenuBarBackendProvider.current.canAssign(clock, to: .hidden, experimentalSystemItemHiding: false))
        try #require(MenuBarBackendProvider.current.canAssign(clock, to: .hidden, experimentalSystemItemHiding: true))
        MenuBarSearchItemActions.postAssignmentRefusal(
            for: clock,
            to: .hidden,
            experimentalSystemItemHiding: false,
            appState: world.appState
        )
        let refusal = try #require(world.appState.layoutFeedback.refusal)
        let expected = LayoutBarFeedbackCenter.systemItemHidingDisabled(itemName: clock.displayName, section: .hidden)
        #expect(refusal.title == expected.title)
        #expect(refusal.message == expected.message)
    }

    @Test("A refusal the setting would not lift says the item stays put, even with the setting off")
    func refusalWithSettingOffForAFixedItem() throws {
        let world = World()
        let control = World.item(.visibleControlItem)
        MenuBarSearchItemActions.postAssignmentRefusal(
            for: control,
            to: .hidden,
            experimentalSystemItemHiding: false,
            appState: world.appState
        )
        let refusal = try #require(world.appState.layoutFeedback.refusal)
        let expected = LayoutBarFeedbackCenter.itemCannotMove(itemName: control.displayName, section: .hidden)
        #expect(refusal.message == expected.message)
    }

    @Test("A grouped item crosses sections with every member of its group, in display order")
    func groupTravelsTogether() throws {
        let world = World()
        let pair = ["One", "Two"].map {
            World.item(MenuBarItemTag(namespace: .string("com.example.Pair"), title: $0, instanceIndex: 0))
        }
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([pair[0], pair[1], alpha, beta])
        try #require(world.appState.itemGroupManager.createGroup(name: "Duo", items: [alpha, beta]) != nil)

        let duo = MenuBarSearchItemActions.crossSectionGroupMembers(for: beta, in: .visible, appState: world.appState)
        #expect(duo == [alpha, beta])
        let app = MenuBarSearchItemActions.crossSectionGroupMembers(for: pair[1], in: .visible, appState: world.appState)
        #expect(app == pair, "an app's own items group automatically")
        #expect(MenuBarSearchItemActions.groupDisplayName(for: [alpha, beta], in: [alpha, beta], appState: world.appState) == "Duo")
    }

    @Test("A loose item crosses sections alone, and an item that is not in the section has no group there")
    func looseItemTravelsAlone() {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([alpha, beta])
        #expect(MenuBarSearchItemActions.crossSectionGroupMembers(for: alpha, in: .visible, appState: world.appState) == nil)
        #expect(MenuBarSearchItemActions.crossSectionGroupMembers(for: alpha, in: .hidden, appState: world.appState) == nil)
    }
}
