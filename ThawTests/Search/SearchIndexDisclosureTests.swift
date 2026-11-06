//
//  SearchIndexDisclosureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Search results open the part of the pane that holds them")
struct SearchIndexDisclosureTests {
    private func entry(_ id: String) throws -> SearchEntry {
        try #require(SearchIndex.entries.first { $0.id == id })
    }

    @Test("Shape fill and Background open their own Appearance sections, the shape itself none")
    func appearanceDisclosures() throws {
        #expect(try entry("appearance.shapeFill").disclosure == .appearanceInsideShape)
        #expect(try entry("appearance.background").disclosure == .appearanceBehindShape)
        #expect(try entry("appearance.shape").disclosure == nil)
    }

    @Test("Entries for a pane are exactly that pane's share of the index")
    func entriesPerPane() {
        let appearance = SearchIndex.entries(for: .menuBarAppearance)
        #expect(!appearance.isEmpty)
        #expect(appearance.allSatisfy { $0.pane == .menuBarAppearance })
        #expect(appearance.count == SearchIndex.entries.count { $0.pane == .menuBarAppearance })
    }

    @Test("A result group is identified by its pane")
    func groupIdentity() {
        let group = SearchGroup(pane: .hotkeys, entries: SearchIndex.entries(for: .hotkeys))
        #expect(group.id == SettingsNavigationIdentifier.hotkeys.rawValue)
    }
}
