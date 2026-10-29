//
//  MenuBarSearchRecentsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The search panel's recents, stored in a throwaway suite.
@MainActor
@Suite("Search recents", .serialized)
struct MenuBarSearchRecentsTests {
    private typealias World = LayoutEditorWorld

    private func recents(_ suites: ScratchSuites) throws -> MenuBarSearchRecents {
        try MenuBarSearchRecents(defaults: #require(suites.make()))
    }

    private func identifier(_ item: MenuBarItem) -> String? {
        MenuBarItemTag.canonicalPersistentIdentifiers([item.tag.tagIdentifier]).first
    }

    @Test("A fresh store has no recents and resolves to nothing")
    func emptyStore() throws {
        let suites = ScratchSuites(prefix: "SearchRecents")
        let recents = try recents(suites)
        let world = World()
        world.seat([World.item("Alpha")])
        #expect(recents.identifiers.isEmpty)
        #expect(recents.resolve(in: world.appState.itemManager).isEmpty)
    }

    @Test("Recording moves an item to the front without listing it twice")
    func recordMovesToFront() throws {
        let suites = ScratchSuites(prefix: "SearchRecents")
        let recents = try recents(suites)
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        recents.record(alpha)
        recents.record(beta)
        recents.record(alpha)
        #expect(recents.identifiers == [identifier(alpha), identifier(beta)].compactMap(\.self))
    }

    @Test("Only the eight most recent items are kept")
    func capsAtEight() throws {
        let suites = ScratchSuites(prefix: "SearchRecents")
        let recents = try recents(suites)
        let items = (0 ..< 10).map { World.item("Item\($0)") }
        items.forEach(recents.record)
        #expect(recents.identifiers.count == 8)
        #expect(recents.identifiers.first == identifier(items[9]))
        #expect(!recents.identifiers.contains { $0 == identifier(items[0]) })
    }

    @Test("Resolving keeps recency order across sections and skips items that are gone")
    func resolveAcrossSections() throws {
        let suites = ScratchSuites(prefix: "SearchRecents")
        let recents = try recents(suites)
        let world = World()
        let visible = World.item("Visible")
        let hidden = World.item("Hidden")
        let gone = World.item("Gone")
        world.seat([visible], in: .visible)
        world.seat([hidden, World.item(.hiddenControlItem)], in: .hidden)
        recents.record(visible)
        recents.record(gone)
        recents.record(hidden)

        let resolved = recents.resolve(in: world.appState.itemManager)
        #expect(resolved.map(\.tag) == [hidden.tag, visible.tag])
        #expect(recents.identifiers.count == 3, "an entry with no live item stays stored")
    }

    @Test("Resolving against a cache lists only the items that cache holds")
    func resolveAgainstACache() throws {
        let suites = ScratchSuites(prefix: "SearchRecents")
        let recents = try recents(suites)
        let kept = World.item("Kept")
        let dropped = World.item("Dropped")
        recents.record(kept)
        recents.record(dropped)
        var cache = MenuBarItemCache(displayID: nil)
        cache[.hidden] = [kept]

        #expect(recents.resolve(in: cache).map(\.tag) == [kept.tag])
    }
}
