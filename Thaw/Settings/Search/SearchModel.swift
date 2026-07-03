//
//  SearchModel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
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

// MARK: - SearchModel

/// The model behind the settings sidebar search.
///
/// Uses ``Fuse`` to fuzzy-match the static ``SearchIndex``, then groups
/// the ranked results by pane into ``SearchGroup``s for
/// ``SearchResultsList``.
@MainActor
final class SearchModel: ObservableObject {
    @Published var searchText = ""
    @Published var displayedGroups = [SearchGroup]()

    let fuse = Fuse(threshold: 0.5)

    /// Rebuilds `displayedGroups` from the current `searchText`.
    func updateDisplayedItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            // The view renders the normal pane list when the query is empty, so
            // the model only ever owns filtered results.
            displayedGroups = []
            return
        }

        struct SearchItem: Searchable {
            let entry: SearchEntry

            var properties: [FuseProp] {
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
                return props
            }
        }

        let searchItems = SearchIndex.entries.map { SearchItem(entry: $0) }

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
