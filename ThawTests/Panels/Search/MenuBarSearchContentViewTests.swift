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

/// The search panel hosted off screen in each layout, read through the results it lists.
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

        init(_ presentation: SearchPresentation = .extended, visible: [MenuBarItem] = [], hidden: [MenuBarItem] = []) {
            world.seat(visible, in: .visible)
            world.seat(hidden, in: .hidden)
            // Items owned by the test process all take its name, so each gets its title as a custom name to search by.
            let names = Dictionary((visible + hidden).map { ($0.uniqueIdentifier, $0.title ?? "") }, uniquingKeysWith: { first, _ in first })
            Defaults.set(names, forKey: .menuBarItemCustomNames)
            panel.performSetup(with: world.appState, displayInvalidations: PassthroughSubject<Void, Never>())
            let root = MenuBarSearchRootView(appState: world.appState, model: panel.model, panel: panel, presentation: presentation)
            render = OffscreenRender(root, size: SearchPanelGeometry.windowSize(isCollapsed: false))
        }

        var ids: [MenuBarSearchModel.ItemID] {
            model.results.map(\.id)
        }

        func settle(within timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
            await render.settle(within: timeout, until: condition)
        }
    }

    private static func itemID(_ item: MenuBarItem) -> MenuBarSearchModel.ItemID {
        MenuBarSearchModel.ItemID(item)
    }

    @Test("Every item is listed under its section before anything is typed, and the first is highlighted")
    func listsEverythingBeforeTyping() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let gamma = World.item("Gamma")
        let harness = Harness(visible: [alpha, beta], hidden: [gamma])
        await harness.settle { harness.model.results.count == 3 }
        #expect(Set(harness.ids) == [Self.itemID(alpha), Self.itemID(beta), Self.itemID(gamma)])
        // With no section engine in the test every item reads as Visible, as in the Layout previews.
        #expect(harness.model.results.allSatisfy { $0.section == MenuBarSection.Name.visible.localizedName })
        #expect(harness.model.selection == harness.ids.first)
    }

    @Test("Items group under their sections in order, right to left within each, and a section turned off is left out")
    func groupsBySection() {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let gamma = World.item("Gamma")
        let delta = World.item("Delta")
        var cache = MenuBarItemCache(displayID: nil)
        cache[.visible] = [alpha, beta]
        cache[.hidden] = [gamma]
        cache[.alwaysHidden] = [delta]
        let candidates = [alpha, beta, gamma, delta].map {
            PaletteCandidate(item: $0, displayName: $0.title ?? "", ownerName: "", identityKey: $0.uniqueIdentifier)
        }

        let all = MenuBarSearchModel.grouped([], in: cache, sections: MenuBarSection.Name.allCases, candidates: candidates)
        #expect(all.map(\.id) == [beta, alpha, gamma, delta].map(Self.itemID))
        #expect(all.map(\.section) == [
            MenuBarSection.Name.visible, .visible, .hidden, .alwaysHidden,
        ].map(\.localizedName))

        let withoutAlwaysHidden = MenuBarSearchModel.grouped([gamma], in: cache, sections: [.visible, .hidden], candidates: candidates)
        #expect(withoutAlwaysHidden.map(\.id) == [gamma, beta, alpha].map(Self.itemID), "a recent item leaves its section")
        #expect(withoutAlwaysHidden.first?.section == String(localized: "Recent"))
    }

    @Test("An item caught mid-move in two sections is listed once, so the arrows don't stall on it")
    func duplicateRowIsListedOnce() {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        var cache = MenuBarItemCache(displayID: nil)
        // The cache can hold the same item in its old and new section until the move settles.
        cache[.visible] = [alpha]
        cache[.hidden] = [alpha, beta]
        let candidates = [alpha, beta].map {
            PaletteCandidate(item: $0, displayName: $0.title ?? "", ownerName: "", identityKey: $0.uniqueIdentifier)
        }

        let results = MenuBarSearchModel.grouped([], in: cache, sections: MenuBarSection.Name.allCases, candidates: candidates)

        #expect(results.map(\.id) == [alpha, beta].map(Self.itemID))
        #expect(results.first?.section == MenuBarSection.Name.visible.localizedName, "the first listing keeps its place")
        #expect(Set(results.map(\.id)).count == results.count)
        #expect(PaletteCandidate.inventory(from: cache).count == 2, "and the palette offers it once too")
    }

    @Test("A query lists the ranked matches, highlighting the best")
    func queryRanks() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let harness = Harness(visible: [alpha, beta])
        await harness.settle { harness.model.results.count == 2 }

        harness.model.searchText = "Beta"
        await harness.settle { harness.ids.first == Self.itemID(beta) }
        #expect(harness.ids.first == Self.itemID(beta))
        #expect(harness.model.results.allSatisfy { $0.section == nil }, "matches carry no headings")
        #expect(harness.model.selection == Self.itemID(beta))
        #expect(!harness.model.candidates.isEmpty, "the inventory is cached for the next keystroke")

        harness.model.searchText = "zzzz"
        await harness.settle { harness.model.results.isEmpty }
        #expect(harness.model.results.isEmpty)
        #expect(harness.model.selection == nil)
    }

    @Test("Recent items are listed once, under Recent, above their sections")
    func recentsOnTop() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        MenuBarSearchRecents().record(beta)
        let harness = Harness(visible: [alpha, beta])
        await harness.settle { harness.model.results.count == 2 }
        #expect(harness.ids == [Self.itemID(beta), Self.itemID(alpha)])
        #expect(harness.model.results.map(\.section) == [String(localized: "Recent"), MenuBarSection.Name.visible.localizedName])

        harness.model.searchText = "Alpha"
        await harness.settle { harness.model.results.allSatisfy { $0.section == nil } }
        #expect(harness.ids.first == Self.itemID(alpha))
    }

    @Test("A recent item that is no longer on the bar leaves no heading behind")
    func staleRecentsAreSkipped() async {
        let alpha = World.item("Alpha")
        MenuBarSearchRecents().record(World.item("Gone"))
        let harness = Harness(visible: [alpha])
        await harness.settle { !harness.model.results.isEmpty }
        #expect(harness.ids == [Self.itemID(alpha)])
        #expect(harness.model.results.first?.section == MenuBarSection.Name.visible.localizedName, "no Recent heading")
    }

    @Test("The arrows walk from the recents down through every row once, and stop at the end")
    func arrowsWalkEveryRow() async {
        let items = ["Alpha", "Beta", "Gamma"].map { World.item($0) }
        MenuBarSearchRecents().record(items[1])
        let harness = Harness(visible: items)
        await harness.settle { harness.model.results.count == 3 }

        var visited = [harness.model.selection]
        for _ in 0 ..< 3 {
            harness.model.moveSelection(by: 1)
            visited.append(harness.model.selection)
        }
        #expect(Array(visited.prefix(3)) == harness.ids.map(Optional.some))
        #expect(visited.last == harness.ids.last, "the last row holds at the end")

        harness.model.moveSelection(by: -(Int.max / 2))
        #expect(harness.model.selection == harness.ids.first, "Home goes to the first row")
    }

    @Test("Tab jumps to the next section's first row and Shift-Tab back, wrapping; matches have no sections")
    func tabJumpsSections() {
        let model = MenuBarSearchModel()
        let items = ["Alpha", "Beta", "Gamma", "Delta"].map { World.item($0) }
        let sections = ["Visible", "Visible", "Hidden", "Always Hidden"]
        model.results = zip(items, sections).map { MenuBarSearchResult(item: $0, ownerName: nil, section: $1) }
        model.selection = Self.itemID(items[1])

        model.moveSelection(toSectionFromCurrentBy: 1)
        #expect(model.selection == Self.itemID(items[2]))
        model.moveSelection(toSectionFromCurrentBy: 1)
        #expect(model.selection == Self.itemID(items[3]))
        model.moveSelection(toSectionFromCurrentBy: 1)
        #expect(model.selection == Self.itemID(items[0]), "past the last section it wraps to the first")
        model.moveSelection(toSectionFromCurrentBy: -1)
        #expect(model.selection == Self.itemID(items[3]), "and back")

        model.results = items.map { MenuBarSearchResult(item: $0, ownerName: nil, section: nil) }
        model.selection = Self.itemID(items[1])
        model.moveSelection(toSectionFromCurrentBy: 1)
        #expect(model.selection == Self.itemID(items[1]), "ranked matches stay put")
    }

    @Test("A turnover of the item cache rebuilds the list and keeps a highlight that is still listed")
    func cacheTurnoverRebuilds() async {
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        let harness = Harness(visible: [alpha, beta])
        await harness.settle { harness.model.results.count == 2 }
        harness.model.selection = Self.itemID(beta)

        let gamma = World.item("Gamma")
        Defaults.set(["\(gamma.uniqueIdentifier)": "Gamma", "\(beta.uniqueIdentifier)": "Beta"], forKey: .menuBarItemCustomNames)
        harness.world.seat([beta, gamma], in: .visible)
        await harness.settle { harness.ids.contains(Self.itemID(gamma)) }
        #expect(Set(harness.ids) == [Self.itemID(beta), Self.itemID(gamma)])
        #expect(harness.model.selection == Self.itemID(beta), "the highlight stays on its row")

        harness.world.seat([gamma], in: .visible)
        await harness.settle { !harness.ids.contains(Self.itemID(beta)) }
        #expect(harness.model.selection == Self.itemID(gamma), "a highlight that is gone moves to the first row")
    }

    @Test("Opening a row does nothing while that row is being renamed")
    func activateIgnoredWhileRenaming() async {
        let alpha = World.item("Alpha")
        let harness = Harness(visible: [alpha])
        await harness.settle { harness.ids.contains(Self.itemID(alpha)) }
        harness.world.appState.navigationState.isSearchPresented = true
        harness.model.renameSession = .init(tag: alpha.tag, windowID: alpha.windowID, draft: "")

        harness.panel.activate(alpha)
        #expect(harness.world.appState.navigationState.isSearchPresented, "the panel stays up")
        #expect(harness.model.renameSession != nil)
    }

    @Test("Both layouts draw, and Compact draws less until something is typed")
    func layoutsDraw() async throws {
        let items = [World.item("Alpha"), World.item("Beta")]
        let extended = Harness(.extended, visible: items)
        await extended.settle { extended.model.results.count == 2 }
        let compact = Harness(.compact, visible: items)
        await compact.settle { compact.model.results.count == 2 }

        let extendedPixels = try extended.render.pixels()
        let compactPixels = try compact.render.pixels()
        #expect(extendedPixels.contains { $0 != 0 })
        #expect(compactPixels.contains { $0 != 0 })
        #expect(extendedPixels.count(where: { $0 != 0 }) > compactPixels.count(where: { $0 != 0 }))
    }
}
