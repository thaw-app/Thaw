//
//  SearchIndexTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers the rules applied around the settings search index: the pane
/// filter, the relevance sort, the disclosure mapping that decides which
/// rows need a collapsed group expanded before they can be revealed, and the
/// non-searchable allow-list.
///
/// The index contents themselves are data, so these assertions target the
/// rules rather than pinning every row — a pinned row list would break on
/// every copy change without catching a real defect.
@Suite("Settings search index")
struct SearchIndexTests {
    // MARK: - entries

    @Test("Every entry has a unique identifier")
    func identifiersAreUnique() {
        // Identifiers are the `Identifiable` key for the result list and the
        // switch key for `disclosure`, so a duplicate is a real defect.
        let ids = SearchIndex.entries.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test("The index is populated")
    func indexIsNotEmpty() {
        #expect(!SearchIndex.entries.isEmpty)
    }

    // MARK: - entries(for:)

    @Test(
        "Filtering by pane returns only that pane's rows",
        arguments: [
            SettingsNavigationIdentifier.general,
            .advanced,
            .hotkeys,
        ]
    )
    func entriesForPaneAreScoped(pane: SettingsNavigationIdentifier) {
        let entries = SearchIndex.entries(for: pane)

        #expect(!entries.isEmpty, "expected indexed rows for \(pane.rawValue)")
        #expect(
            entries.allSatisfy { $0.pane == pane },
            "entries(for: \(pane.rawValue)) leaked a row from another pane"
        )
    }

    @Test("Filtering by pane partitions the whole index")
    func entriesForPanePartitionsTheIndex() {
        let partitioned = SettingsNavigationIdentifier.allCases
            .flatMap { SearchIndex.entries(for: $0) }

        #expect(partitioned.count == SearchIndex.entries.count)
    }

    @Test("New trigger panes have searchable pane rows")
    func triggerPanesAreSearchable() {
        #expect(SearchIndex.entries(for: .triggers).contains { $0.id == "pane.triggers" })
        #expect(SearchIndex.entries(for: .developer).contains { $0.id == "pane.developer" })
    }

    // MARK: - sortedByRelevance

    @Test("The lowest diff score sorts first")
    func lowestDiffScoreWins() {
        // Fuse scores 0 for a perfect match and climbs as the match gets
        // worse, so the best result is the smallest number.
        let sorted = SearchIndex.sortedByRelevance([
            (item: "worst", diffScore: 0.9),
            (item: "best", diffScore: 0.0),
            (item: "middle", diffScore: 0.4),
        ])

        #expect(sorted == ["best", "middle", "worst"])
    }

    @Test("Sorting an empty result set is empty")
    func sortingEmptyInput() {
        let sorted: [String] = SearchIndex.sortedByRelevance([])

        #expect(sorted.isEmpty)
    }

    // MARK: - disclosure

    @Test(
        "Layout-control rows request their disclosure group",
        arguments: [
            "advanced.alwaysUseAppIconForMenuBarItems",
            "advanced.enableMenuBarItemOverflow",
            "advanced.useThawBarOnNotchOverflow",
            "advanced.menuBarOrderFulfillmentTimeout",
        ]
    )
    func gatedRowsRequestDisclosure(id: String) {
        // These rows live inside a collapsed group in the Advanced pane.
        // Without the disclosure, selecting the search result scrolls to a
        // row the user cannot see. A row absent on this OS version is not a
        // failure; the mapping is only asserted for the ones indexed here.
        guard let entry = SearchIndex.entries.first(where: { $0.id == id }) else {
            return
        }

        #expect(entry.disclosure == .advancedLayoutControls)
    }

    @Test("Rows outside the Advanced pane need no disclosure")
    func ungatedRowsNeedNoDisclosure() {
        let ungated = SearchIndex.entries.filter { !$0.id.hasPrefix("advanced.") }

        #expect(!ungated.isEmpty)
        #expect(ungated.allSatisfy { $0.disclosure == nil })
    }

    // MARK: - nonSearchableProperties

    @Test("Deprecated properties are exempt from the drift guard")
    func deprecatedPropertiesAreExempt() {
        // These are deprecated, internal, or commented out of the UI, so
        // their absence from the index is intentional rather than drift.
        let exempt = SearchIndex.nonSearchableProperties

        #expect(exempt.contains(.general("useIceBar")))
        #expect(exempt.contains(.general("iceBarLocation")))
        #expect(exempt.contains(.advanced("enableExperimentalOverflowPrevention")))
        #expect(exempt.contains(.advanced("enableExperimentalWindowHiding")))
    }

    @Test("Exempt properties are genuinely absent from the index")
    func exemptPropertiesAreNotIndexed() {
        // The allow-list only means something if the listed properties
        // really are missing; a property that is both indexed and exempt
        // would hide future drift.
        let indexed = Set(SearchIndex.entries.compactMap(\.property))

        for property in SearchIndex.nonSearchableProperties {
            #expect(
                !indexed.contains(property),
                "\(property) is indexed but also listed as non-searchable"
            )
        }
    }
}
