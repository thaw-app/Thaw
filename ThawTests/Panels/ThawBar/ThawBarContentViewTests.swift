//
//  ThawBarContentViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// The Thaw Bar's content in each layout and empty state, hosted off screen.
@MainActor
@Suite("Thaw Bar content", .serialized, .scratchDefaults)
struct ThawBarContentViewTests {
    private typealias World = LayoutEditorWorld

    @MainActor
    private final class Harness {
        let world = World()
        let focus = ThawBarKeyboardFocus()
        let screen: NSScreen

        init() throws {
            screen = try #require(NSScreen.main)
        }

        func use(_ layout: ThawBarLayout, columns: Int = 2) throws {
            let uuid = try #require(Bridging.getDisplayUUIDString(for: screen.displayID))
            world.appState.settings.displaySettings.updateConfiguration(forDisplayUUID: uuid) {
                $0.withThawBarLayout(layout).withGridColumns(columns)
            }
        }

        func render(_ section: MenuBarSection.Name, folderMembers: [String]? = nil) -> OffscreenRender<some View> {
            let appState = world.appState
            let view = ThawBarContentView(
                appState: appState,
                colorManager: ThawBarColorManager(),
                keyboardFocus: focus,
                itemManager: appState.itemManager,
                imageCache: appState.imageCache,
                menuBarManager: appState.menuBarManager,
                visibleControlItem: nil,
                screen: screen,
                section: section,
                folderMembers: folderMembers
            )
            return OffscreenRender(view, size: CGSize(width: 400, height: 300))
        }
    }

    @Test("The keyboard highlight follows the item count and maps arrows to the layout", arguments: [
        ThawBarLayout.horizontal, .vertical, .grid,
    ])
    func keyboardFollowsLayout(layout: ThawBarLayout) async throws {
        let harness = try Harness()
        try harness.use(layout, columns: 2)
        let items = ["Alpha", "Beta", "Gamma"].map(World.item)
        harness.world.seat(items, in: .hidden)
        let render = harness.render(.hidden)
        await render.settle(within: .seconds(5)) {
            harness.focus.begin()
            return harness.focus.index == 0
        }
        #expect(harness.focus.index == 0, "three items give the keyboard a first item to land on")

        // Down moves one row: one item in a column, two in a two-column grid, nothing in a row.
        harness.focus.move(dx: 0, dy: 1)
        let expected = switch layout {
        case .horizontal: 0
        case .vertical: 1
        case .grid: 2
        }
        #expect(harness.focus.index == expected)
        #expect(try render.pixels().contains { $0 != 0 }, "the bar draws its chrome and items")
    }

    @Test("An empty hidden section says so once the loading grace period ends")
    func emptySectionExplains() async throws {
        let harness = try Harness()
        harness.world.seat([World.item("Alpha")], in: .visible)
        let render = harness.render(.alwaysHidden)
        let loading = try render.pixels()
        await render.settle(within: .seconds(5)) { (try? render.pixels()) != loading }
        #expect(try render.pixels() != loading, "the loading row gives way to the empty state")
        harness.focus.begin()
        #expect(harness.focus.index == nil, "an empty bar has nothing to highlight")
    }

    @Test("A bar with no items at all shows a loading row, then the failure row")
    func noItemsAtAll() async throws {
        let harness = try Harness()
        let render = harness.render(.visible)
        let loading = try render.pixels()
        #expect(loading.contains { $0 != 0 })
        await render.settle(within: .seconds(8)) { (try? render.pixels()) != loading }
        #expect(try render.pixels() != loading, "the load times out into the failure row")
    }

    @Test("A folder lists only its members, in folder order")
    func folderListsMembers() async throws {
        let harness = try Harness()
        let items = ["Alpha", "Beta", "Gamma"].map(World.item)
        harness.world.seat(items, in: .visible)
        let members = [items[2], items[0]].map { MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) }
        let render = harness.render(.visible, folderMembers: members)
        await render.settle(within: .seconds(5)) {
            harness.focus.begin()
            harness.focus.move(dx: 1, dy: 0)
            harness.focus.move(dx: 1, dy: 0)
            return harness.focus.index == 1
        }
        #expect(harness.focus.index == 1, "two folder members leave the highlight on the second")
    }
}
