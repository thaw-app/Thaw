//
//  MenuBarSearchFooterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import SwiftUI
import Testing
@testable import Thaw

/// The bar under the search list, with the shortcut bar on and off.
@MainActor
@Suite("Search panel footer", .serialized, .scratchDefaults)
struct MenuBarSearchFooterTests {
    private typealias World = LayoutEditorWorld

    private struct Hosted: View {
        let world: World
        let panel: MenuBarSearchPanel

        var body: some View {
            MenuBarSearchFooter(panel: panel)
                .environment(world.appState)
                .environment(panel.model)
                .defaultAppStorage(Defaults.store)
        }
    }

    private static func render(_ world: World, _ panel: MenuBarSearchPanel) -> OffscreenRender<Hosted> {
        OffscreenRender(Hosted(world: world, panel: panel), size: CGSize(width: 480, height: 160))
    }

    @Test("With the shortcut bar off, nothing is drawn until a move is refused, and then the notice is")
    func hiddenBarKeepsTheNotice() async {
        Defaults.set(false, forKey: .showSearchShortcutBar)
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        panel.model.results = [MenuBarSearchResult(item: alpha, ownerName: nil, section: nil)]
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        let render = Self.render(world, panel)
        #expect(render.host.fittingSize.height == 0, "no bar, no notice")
        #expect(panel.itemActionsAnchor == nil, "the Actions button is not there to anchor ⌘K")

        world.appState.layoutFeedback.post(LayoutBarFeedbackCenter.itemNotMovable(itemName: "Alpha"))
        await render.settle { render.host.fittingSize.height > 0 }
        #expect(render.host.fittingSize.height > 0, "the refusal still shows")
    }

    @Test("With the shortcut bar on, it draws for the highlighted row and anchors ⌘K's menu")
    func shownBar() async {
        Defaults.set(true, forKey: .showSearchShortcutBar)
        let world = World()
        let alpha = World.item("Alpha")
        world.seat([alpha])
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
        panel.model.results = [MenuBarSearchResult(item: alpha, ownerName: nil, section: nil)]
        panel.model.selection = MenuBarSearchModel.ItemID(alpha)
        let render = Self.render(world, panel)
        await render.settle { panel.itemActionsAnchor != nil }
        #expect(render.host.fittingSize.height > 0)
        #expect(panel.itemActionsAnchor != nil)
    }
}
