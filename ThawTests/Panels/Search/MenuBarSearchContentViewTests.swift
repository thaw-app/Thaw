//
//  MenuBarSearchContentViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// The search interface hosted off screen in each face, read through the rows it builds.
@MainActor
@Suite("Search panel content", .serialized, .scratchDefaults)
struct MenuBarSearchContentViewTests {
    private typealias World = LayoutEditorWorld

    /// A search panel that is never shown, its content hosted in an offscreen window.
    @MainActor
    private final class Harness {
        let world = World()
        let panel = MenuBarSearchPanel()
        let render: OffscreenRender<MenuBarSearchRootView>

        var model: MenuBarSearchModel {
            panel.model
        }

        init(_ presentation: SearchPresentation, visible: [MenuBarItem] = [], hidden: [MenuBarItem] = []) {
            world.seat(visible, in: .visible)
            world.seat(hidden, in: .hidden)
            // Items owned by the test process all take its name, so each gets its title as a custom name to search by.
            let names = Dictionary((visible + hidden).map { ($0.uniqueIdentifier, $0.title ?? "") }, uniquingKeysWith: { first, _ in first })
            Defaults.set(names, forKey: .menuBarItemCustomNames)
            panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
            let root = MenuBarSearchRootView(
                appState: world.appState,
                model: panel.model,
                displayID: CGMainDisplayID(),
                panel: panel,
                presentation: presentation
            )
            render = OffscreenRender(root, size: presentation.contentSize)
        }

        var ids: [MenuBarSearchModel.ItemID] {
            model.displayedItems.map(\.id)
        }

        func settle(within timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
            await render.settle(within: timeout, until: condition)
        }
    }

    private static func itemID(_ item: MenuBarItem) -> MenuBarSearchModel.ItemID {
        .item(item.tag, windowID: item.windowID)
    }

    @Test("The inspector lists every section under its heading, items right to left")
    func inspectorListsSections() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let gamma = World.item("Gamma")
        let harness = Harness(.inspector, visible: [alpha, beta, World.item(.visibleControlItem)], hidden: [gamma])
        await harness.settle { !harness.model.displayedItems.isEmpty }

        let ids = harness.ids
        #expect(ids.prefix(3) == [.header(.visible), Self.itemID(beta), Self.itemID(alpha)])
        #expect(ids.contains(.header(.hidden)))
        #expect(ids.contains(Self.itemID(gamma)))
        #expect(!harness.model.displayedItems.contains { $0.id == .header(.visible) && $0.isSelectable })
        #expect(harness.model.selection == Self.itemID(beta), "the first item row is highlighted")
    }

    @Test("A query in the inspector ranks matching items and drops the headings")
    func inspectorQueryRanks() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let harness = Harness(.inspector, visible: [alpha, beta])
        await harness.settle { !harness.model.displayedItems.isEmpty }

        harness.model.searchText = "Beta"
        await harness.settle { harness.ids.first == Self.itemID(beta) }
        #expect(harness.ids.first == Self.itemID(beta))
        #expect(!harness.ids.contains(.header(.visible)))
        #expect(harness.model.selection == Self.itemID(beta))

        harness.model.searchText = "zzzzqqqq"
        await harness.settle { harness.model.displayedItems.isEmpty }
        #expect(harness.model.displayedItems.isEmpty)
        #expect(harness.model.selection == nil)
    }

    @Test("A turned-over item cache rebuilds the rows")
    func cacheTurnoverRebuilds() async {
        let alpha = World.item("Alpha")
        let harness = Harness(.inspector, visible: [alpha])
        await harness.settle { harness.ids.contains(Self.itemID(alpha)) }

        let beta = World.item("Beta")
        harness.world.seat([alpha, beta])
        await harness.settle { harness.ids.contains(Self.itemID(beta)) }
        #expect(harness.ids.contains(Self.itemID(beta)))
    }

    @Test("The inspector draws its bottom bar for the highlighted row, and the rename buttons while renaming")
    func inspectorBottomBarStates() async throws {
        let alpha = World.item("Alpha")
        let harness = Harness(.inspector, visible: [alpha])
        await harness.settle { harness.model.selection != nil }
        let browsing = try harness.render.pixels()

        harness.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "Draft")
        await harness.settle { (try? harness.render.pixels()) != browsing }
        #expect(try harness.render.pixels() != browsing, "the rename swaps the row and the buttons")

        harness.world.appState.layoutFeedback.post(LayoutBarFeedbackCenter.itemNotMovable(itemName: "Alpha"))
        harness.model.renameSession = nil
        let withNotice = try harness.render.pixels()
        harness.world.appState.layoutFeedback.clear()
        await harness.settle { (try? harness.render.pixels()) != withNotice }
        #expect(try harness.render.pixels() != withNotice, "dismissing the refusal redraws the bar")
    }

    @Test("A row's action does nothing while that row is being renamed")
    func actionIgnoredWhileRenaming() async throws {
        let alpha = World.item("Alpha")
        let harness = Harness(.inspector, visible: [alpha])
        await harness.settle { harness.ids.contains(Self.itemID(alpha)) }
        harness.world.appState.navigationState.isSearchPresented = true
        harness.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "")

        let row = try #require(harness.model.displayedItems.first { $0.id == Self.itemID(alpha) })
        row.action?()
        #expect(harness.world.appState.navigationState.isSearchPresented, "the panel stays up")
        #expect(harness.model.renameSession != nil)
    }

    @Test("The launcher lists nothing until the user types, then the ranked matches")
    func launcherWaitsForAQuery() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let harness = Harness(.launcher, visible: [alpha, beta])
        await harness.settle(within: .milliseconds(200)) { false }
        #expect(harness.model.displayedItems.isEmpty)

        harness.model.searchText = "Alpha"
        await harness.settle { harness.ids.first == Self.itemID(alpha) }
        #expect(harness.ids.first == Self.itemID(alpha))
        #expect(!harness.model.launcherCandidates.isEmpty, "the inventory is cached for the next keystroke")
        #expect(harness.model.selection == Self.itemID(alpha))
    }

    @Test("The assisted face lists the whole inventory before anything is typed")
    func assistedListsEverything() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let harness = Harness(.assisted, visible: [alpha, beta])
        await harness.settle { harness.model.displayedItems.count == 2 }
        #expect(Set(harness.ids) == [Self.itemID(alpha), Self.itemID(beta)])

        harness.model.searchText = "Beta"
        await harness.settle { harness.ids == [Self.itemID(beta)] }
        #expect(harness.ids.first == Self.itemID(beta))
    }

    @Test("Each face draws a different surface for the same items")
    func facesDrawDifferently() async throws {
        let items = [World.item("Alpha"), World.item("Beta")]
        var drawn = [Data]()
        for presentation in SearchPresentation.allCases {
            let harness = Harness(presentation, visible: items)
            harness.model.searchText = "a"
            await harness.settle { !harness.model.displayedItems.isEmpty }
            let pixels = try harness.render.pixels()
            #expect(pixels.contains { $0 != 0 }, "the \(presentation) face draws something")
            drawn.append(pixels)
        }
        #expect(Set(drawn).count == drawn.count)
    }
}
