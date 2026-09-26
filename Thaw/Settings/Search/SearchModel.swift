//
//  SearchModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Ifrit
import Observation
import SwiftUI

// MARK: - SearchGroup

/// A group of search results that belong to the same settings pane.
struct SearchGroup: Identifiable {
    let pane: SettingsNavigationIdentifier
    let entries: [SearchEntry]

    var id: String {
        pane.rawValue
    }
}

// MARK: - SearchItem

/// A precomputed searchable wrapper around a ``SearchEntry``.
///
/// The `properties` are built once at initialization rather than re-derived
/// on every fuzzy search, so the static corpus is tokenized a single time.
private struct SearchItem: Searchable {
    let entry: SearchEntry
    let properties: [FuseProp]

    init(entry: SearchEntry, bundle: Bundle = .main) {
        self.entry = entry
        // Weight the title highest, then keywords, then the description.
        // Lower weight values contribute less to the diff score, so a
        // match in the title ranks above a match in the description.
        let weights = SearchWeights.settings
        // Match against what the pane actually renders, so a translated
        // build is searchable in its own language.
        let localizedTitle = entry.localizedTitle(bundle: bundle)
        var props = [FuseProp(localizedTitle, weight: weights.title)]
        if localizedTitle != entry.titleText {
            // Keep the English source matchable too — users search the term
            // they saw in the docs as often as the one on screen.
            props.append(FuseProp(entry.titleText, weight: weights.title))
        }
        if !entry.keywords.isEmpty {
            props.append(FuseProp(entry.keywords.joined(separator: " "), weight: weights.keywords))
        }
        if let descriptionText = entry.localizedDescription(bundle: bundle) {
            props.append(FuseProp(descriptionText, weight: weights.description))
        }
        self.properties = props
    }
}

// MARK: - SearchModel

/// The model behind the settings sidebar search.
///
/// Uses ``Fuse`` to fuzzy-match the static ``SearchIndex``, then groups
/// the ranked results by pane into ``SearchGroup``s for
/// ``SearchResultsList``.
@MainActor
@Observable
final class SearchModel {
    var searchText = "" {
        didSet {
            updateDisplayedItems()
        }
    }

    var displayedGroups = [SearchGroup]()

    let fuse = Fuse(threshold: 0.5)

    /// The static search corpus, tokenized once and reused across queries.
    private let searchItems = SearchIndex.entries.map { SearchItem(entry: $0) }

    /// Ranks the whole index against `query`, resolving titles against
    /// `bundle`.
    ///
    /// The instance path resolves against `Bundle.main`, whose localization a
    /// test process cannot switch; this exposes the same ranking with the
    /// bundle injected so translated matching is verifiable.
    static func rankedEntries(for query: String, bundle: Bundle) -> [SearchEntry] {
        let items = SearchIndex.entries.map { SearchItem(entry: $0, bundle: bundle) }
        let results = Fuse(threshold: 0.5).searchSync(query, in: items, by: \.properties)
        let scored = results.map { (item: items[$0.index], diffScore: $0.diffScore) }
        return SearchIndex.sortedByRelevance(scored).map(\.entry)
    }

    /// Rebuilds `displayedGroups` from the current `searchText`.
    func updateDisplayedItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            // The view renders the normal pane list when the query is empty, so
            // the model only ever owns filtered results.
            displayedGroups = []
            return
        }

        let fuseResults = fuse.searchSync(query, in: searchItems, by: \.properties)

        let scored = fuseResults.map { result in
            (item: searchItems[result.index], diffScore: result.diffScore)
        }

        // Rank globally by relevance, then group by pane preserving the rank
        // order within each pane. Pane order follows the best-scoring entry.
        let ranked = SearchIndex.sortedByRelevance(scored)

        var grouped: [SettingsNavigationIdentifier: [SearchEntry]] = [:]
        var paneOrder: [SettingsNavigationIdentifier] = []
        for item in ranked {
            let pane = item.entry.pane
            if grouped[pane] == nil {
                paneOrder.append(pane)
            }
            grouped[pane, default: []].append(item.entry)
        }

        displayedGroups = paneOrder.map { pane in
            SearchGroup(pane: pane, entries: grouped[pane] ?? [])
        }
    }
}
