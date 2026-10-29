//
//  LayoutBarItemInspectorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// The item inspector popover and the icon picker, rendered off screen against throwaway settings.
@MainActor
@Suite("Layout bar inspector and icon picker", .serialized, .scratchDefaults)
struct LayoutBarItemInspectorTests {
    private typealias World = LayoutEditorWorld

    private func inspector(
        _ item: MenuBarItem,
        orderedItems: [MenuBarItem],
        world: World,
        onShowAllActions: @escaping () -> Void = {}
    ) -> some View {
        LayoutBarItemInspector(
            item: item,
            section: .hidden,
            orderedItems: orderedItems,
            appState: world.appState,
            onShowAllActions: onShowAllActions
        )
    }

    @Test("The inspector lays out at its fixed width and grows a line for the item's position")
    func inspectorLayout() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([alpha, beta], in: .hidden)

        let placed = OffscreenRender(inspector(alpha, orderedItems: [beta, alpha], world: world), size: CGSize(width: 268, height: 400))
        let unplaced = OffscreenRender(inspector(alpha, orderedItems: [], world: world), size: CGSize(width: 268, height: 400))
        #expect(placed.host.fittingSize.width == 268)
        #expect(placed.host.fittingSize.height > unplaced.host.fittingSize.height, "the Position line adds a row")
        #expect(try placed.pixels().contains { $0 != 0 })
    }

    @Test("A custom name and a reveal switch the user turned on are what the inspector opens with")
    func inspectorReadsStoredState() throws {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "Renamed"
        MenuBarItemAlertReveals.setEnabled(true, for: alpha.tag.tagIdentifier)
        let size = CGSize(width: 268, height: 400)
        let stored = try OffscreenRender(inspector(alpha, orderedItems: [alpha], world: world), size: size).pixels()

        alpha.customName = nil
        MenuBarItemAlertReveals.setEnabled(false, for: alpha.tag.tagIdentifier)
        let plain = try OffscreenRender(inspector(alpha, orderedItems: [alpha], world: world), size: size).pixels()
        #expect(stored != plain)
    }

    @Test("Closing the inspector keeps a name the user did not change")
    func closingKeepsTheName() async {
        let world = World()
        var alpha = World.item("Alpha")
        alpha.customName = "Kept"
        let render = OffscreenRender(AnyView(inspector(alpha, orderedItems: [alpha], world: world)), size: CGSize(width: 268, height: 400))
        render.host.rootView = AnyView(EmptyView())
        await render.settle(within: .milliseconds(200)) { false }
        #expect(alpha.customName == "Kept")
    }

    @Test("The icon picker offers the app's icons, or says it found none")
    func iconPicker() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let size = CGSize(width: 460, height: 420)
        let icon = try #require(NSImage(systemSymbolName: "star", accessibilityDescription: nil))
        let candidates = [
            BundledStatusIcon.Candidate(name: "star", image: icon, isLoose: true),
            BundledStatusIcon.Candidate(name: "star2", image: icon, isLoose: false),
        ]
        let withIcons = try OffscreenRender(
            ItemIconPickerView(item: alpha, candidates: candidates, onDone: {}).environment(world.appState),
            size: size
        ).pixels()
        let empty = try OffscreenRender(
            ItemIconPickerView(item: alpha, candidates: [], onDone: {}).environment(world.appState),
            size: size
        ).pixels()
        #expect(withIcons.contains { $0 != 0 })
        #expect(withIcons != empty)
    }
}
