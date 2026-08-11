//
//  SearchRanker.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// MARK: - SearchWeights

/// Field weights for a fuzzy-search `Searchable` conformance.
///
/// Fuse scales a field's diff score by `(1 - weight)` (a weight of `1`
/// leaves it unchanged), and a lower diff score ranks the result higher —
/// so a *higher* weight value means a match in that field ranks the result
/// higher. Not
/// every search surface has all three fields — menu bar item search, for
/// example, has no keywords or description — so callers simply omit the
/// `FuseProp` for any field they don't have.
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
    /// `FuseProp` default weight, preserved here so adopting `SearchRanker`
    /// doesn't change menu-bar-item search ranking.
    static let menuBarItem = SearchWeights(title: 1.0, keywords: 1.0, description: 1.0)
}

// MARK: - SearchRanker

/// Shared fuzzy-search ranking helpers, used by both the settings sidebar
/// search (``SearchModel``) and menu bar item search
/// (``MenuBarSearchPanel``) so the two surfaces can't silently drift apart.
///
/// Deliberately has no dependency on `Ifrit`/`Fuse` so it (and the tests
/// covering it) don't require linking Ifrit into the test target. Each
/// search surface still owns its own `Fuse` instance and `Searchable`
/// conformance; this only standardizes the weighting recipe and the
/// relevance sort applied to Fuse's results.
nonisolated enum SearchRanker {
    /// Pure relevance sort: Fuse's `diffScore` is `0` for a perfect match and
    /// increases with worse matches, so the best result has the lowest score.
    /// Extracted from the search pipeline so it can be unit-tested without
    /// linking Ifrit into the test target.
    static func sortedByRelevance<T>(_ items: [(item: T, diffScore: Double)]) -> [T] {
        items.sorted { $0.diffScore < $1.diffScore }.map(\.item)
    }
}
