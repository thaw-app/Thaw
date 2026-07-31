//
//  SearchModelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
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
        #expect(groups.map(\.id) == groups.map(\.pane.rawValue))
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

    /// The `de` localization inside the app bundle. `String(localized:)`
    /// picks its localization from the bundle, not from its `locale:`
    /// argument, so switching languages in-process means resolving against
    /// the matching `.lproj`.
    private static func localizationBundle(_ identifier: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: identifier, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("Entry titles resolve to the running localization, not the English source")
    func entryTitlesAreLocalized() throws {
        let entry = try #require(SearchIndex.entries.first { $0.id == "general.launchAtLogin" })
        let german = try Self.localizationBundle("de")
        let english = try Self.localizationBundle("en")

        let englishTitle = entry.localizedTitle(bundle: english)
        let germanTitle = entry.localizedTitle(bundle: german)

        #expect(
            englishTitle != germanTitle,
            "the de catalog must translate the title, or localization cannot be observed"
        )

        // Pin the running resolution only when the host's active localization
        // is one of the two catalogs loaded above; asserting a specific
        // language unconditionally would depend on the host's settings.
        if let active = Bundle.main.preferredLocalizations.first {
            if active.hasPrefix("de") {
                #expect(entry.localizedTitle() == germanTitle)
            } else if active.hasPrefix("en") {
                #expect(entry.localizedTitle() == englishTitle)
            }
        }
    }

    @Test("A German query matches the entry whose German title it names")
    func germanQueryMatchesTranslatedTitle() throws {
        // "Einloggen" appears only in the German rendering of
        // "Launch at Login" — nothing in the English index contains it, so a
        // hit proves the translated title is what was indexed.
        let german = try Self.localizationBundle("de")
        let results = SearchModel.rankedEntries(for: "Einloggen", bundle: german)

        #expect(results.contains { $0.id == "general.launchAtLogin" })
    }

    @Test("An English query still matches in a localized build")
    func englishQueryMatchesInLocalizedBuild() throws {
        let german = try Self.localizationBundle("de")
        let results = SearchModel.rankedEntries(for: "Launch at Login", bundle: german)

        #expect(results.contains { $0.id == "general.launchAtLogin" })
    }
}
