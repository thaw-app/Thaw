//
//  SearchRanker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// MARK: - SearchWeights

/// Field weights for a fuzzy-search `Searchable` conformance.
///
/// Fuse scales a field's diff score by `(1 - weight)` and lower scores rank
/// higher, so a higher weight ranks that field's matches higher. Callers
/// omit the `FuseProp` for fields they don't have.
nonisolated struct SearchWeights {
    let title: Double
    let keywords: Double
    let description: Double

    /// The weighting used by the settings sidebar search
    /// (``SearchModel``): a title match ranks above a keywords
    /// match, which ranks above a description match.
    static let settings = SearchWeights(title: 0.6, keywords: 0.3, description: 1.0)

    /// The weighting used by menu bar item search (``MenuBarSearchPanel``),
    /// which only matches on the item's display name. `1.0` is Ifrit's
    /// `FuseProp` default weight.
    static let menuBarItem = SearchWeights(title: 1.0, keywords: 1.0, description: 1.0)
}

// MARK: - SearchRanker

/// Shared fuzzy-search ranking helpers, used by both the settings sidebar
/// search (``SearchModel``) and menu bar item search
/// (``MenuBarSearchPanel``) so the two surfaces can't silently drift apart.
///
/// No `Ifrit` dependency, so its tests don't need Ifrit linked. Each surface
/// still owns its `Fuse` instance and `Searchable` conformance.
nonisolated enum SearchRanker {
    /// Sorts by Fuse `diffScore`, which is `0` for a perfect match, lowest
    /// first.
    static func sortedByRelevance<T>(_ items: [(item: T, diffScore: Double)]) -> [T] {
        items.sorted { $0.diffScore < $1.diffScore }.map(\.item)
    }
}
