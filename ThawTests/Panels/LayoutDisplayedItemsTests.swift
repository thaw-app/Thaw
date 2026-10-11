//
//  LayoutDisplayedItemsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite(.serialized)
struct LayoutDisplayedItemsTests {
    private typealias World = LayoutEditorWorld

    private func shown(_ world: World, in section: MenuBarSection.Name = .visible) -> [MenuBarItem] {
        LayoutDisplayedItems.items(
            in: section,
            appState: world.appState,
            runningApplications: NSWorkspace.shared.runningApplications
        )
    }

    @Test
    func aSectionShowsItsItemsInOrder() {
        let world = World()
        let items = ["A", "B"].map(World.item)
        world.seat(items)

        #expect(shown(world) == items)
        #expect(shown(world, in: .hidden).isEmpty)
    }

    @Test
    func anItemWhoseAppHasQuitIsLeftOut() {
        let world = World()
        let running = World.item("Running")
        let quit = World.item(
            MenuBarItemTag(namespace: .string("com.example.Quit"), title: "Quit", instanceIndex: 0),
            ownerPID: 1
        )
        world.seat([quit, running])

        #expect(LayoutDisplayedItems.items(in: .visible, appState: world.appState, runningApplications: [.current]) == [running])
    }
}
