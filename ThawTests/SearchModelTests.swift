//
//  SearchModelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Testing
@testable import Thaw

@Suite("Settings search model")
@MainActor
struct SearchModelTests {
    @Test("Search results are grouped by pane without losing ranked entries")
    func resultsAreGroupedByPane() {
        let model = SearchModel()

        model.searchText = "hotkey"

        let groups = model.displayedGroups
        let entries = groups.flatMap(\.entries)

        #expect(!groups.isEmpty)
        #expect(entries.count > groups.count, "Expected more than one result in at least one pane")
        #expect(Set(groups.map(\.pane)).count == groups.count)
        #expect(groups.map(\.id) == groups.map { $0.pane.rawValue })
        #expect(groups.allSatisfy { group in
            !group.entries.isEmpty && group.entries.allSatisfy { $0.pane == group.pane }
        })
        #expect(entries.contains { $0.id == "pane.hotkeys" })
        #expect(entries.contains { $0.id == "hotkeys.toggleHiddenSection" })
    }

    @Test("Whitespace clears previously displayed search results")
    func whitespaceClearsResults() {
        let model = SearchModel()
        model.searchText = "hotkey"
        #expect(!model.displayedGroups.isEmpty)

        model.searchText = "  \n\t"

        #expect(model.displayedGroups.isEmpty)
    }
}
