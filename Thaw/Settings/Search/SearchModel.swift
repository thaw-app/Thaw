//
//  SearchModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Ifrit
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

/// A precomputed searchable wrapper around a SearchEntry.
///
/// The properties are built once at initialization rather than re-derived
/// on every fuzzy search, so the static corpus is tokenized a single time.
private struct SearchItem: Searchable {
    let entry: SearchEntry
    let properties: [FuseProp]

    init(entry: SearchEntry) {
        self.entry = entry
        // Weight the title highest, then keywords, then the description.
        // Lower weight values contribute less to the diff score, so a
        // match in the title ranks above a match in the description.
        let weights = SearchWeights.settings
        var props = [FuseProp(entry.titleText, weight: weights.title)]
        if !entry.keywords.isEmpty {
            props.append(FuseProp(entry.keywords.joined(separator: " "), weight: weights.keywords))
        }
        if let descriptionText = entry.descriptionText {
            props.append(FuseProp(descriptionText, weight: weights.description))
        }
        self.properties = props
    }
}

// MARK: - SearchModel

/// The model behind the settings sidebar search.
///
/// Uses Fuse to fuzzy-match the static SearchIndex, then groups
/// the ranked results by pane into SearchGroups for
/// SearchResultsList.
@MainActor
@Observable
final class SearchModel {
    var searchText = "" {
        didSet {
            updateDisplayedItems()
        }
    }

    var displayedGroups = [SearchGroup]()

    @ObservationIgnored
    private var fuse: Fuse?

    /// The static search corpus, materialized lazily on the first non-empty query.
    @ObservationIgnored
    private var searchItems: [SearchItem]?

    /// Rebuilds displayedGroups from the current searchText.
    func updateDisplayedItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            // The view renders the normal pane list when the query is empty, so
            // the model only ever owns filtered results.
            clearIndex()
            return
        }

        let fuse = self.fuse ?? {
            let instance = Fuse(threshold: 0.5)
            self.fuse = instance
            return instance
        }()
        let items = self.searchItems ?? {
            let built = SearchIndex.entries.map(SearchItem.init)
            self.searchItems = built
            return built
        }()

        let fuseResults = fuse.searchSync(query, in: items, by: \.properties)

        let scored = fuseResults.map { result in
            (item: items[result.index], diffScore: result.diffScore)
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

    /// Drops the lazy Fuse matcher, tokenized corpus, and current result groups.
    func clearIndex() {
        displayedGroups = []
        searchItems = nil
        fuse = nil
    }
}
