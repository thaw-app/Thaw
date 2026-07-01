//
//  SearchRankerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - SearchRankerTests

/// Covers the fuzzy-search ranking pipe shared by settings search
/// (`SettingsSearchModel`) and menu bar item search (`MenuBarSearchPanel`).
///
/// `SearchRanker` has no dependency on `Ifrit`/`Fuse`, so — like
/// `SettingsSearchIndexTests` — these tests don't need Ifrit linked into the
/// test target.
final class SearchRankerTests: XCTestCase {
    // MARK: - Relevance Sort

    func testSortedByRelevanceOrdersLowestDiffScoreFirst() {
        let items: [(item: String, diffScore: Double)] = [
            ("worst", 0.9),
            ("best", 0.1),
            ("middle", 0.5),
        ]
        XCTAssertEqual(SearchRanker.sortedByRelevance(items), ["best", "middle", "worst"])
    }

    func testSortedByRelevanceHandlesEmptyInput() {
        let empty: [(item: String, diffScore: Double)] = []
        XCTAssertEqual(SearchRanker.sortedByRelevance(empty), [])
    }

    func testSortedByRelevanceIsStableOnTies() {
        // Equal diff scores must preserve original order, so equally-relevant
        // results don't shuffle between renders (menu bar item search rebuilds
        // `displayedItems` on every keystroke).
        let items: [(item: String, diffScore: Double)] = [
            ("first", 0.4),
            ("second", 0.4),
            ("third", 0.4),
        ]
        XCTAssertEqual(SearchRanker.sortedByRelevance(items), ["first", "second", "third"])
    }

    // MARK: - Drift Guard: Menu Bar Item Weighting

    /// Menu bar item search only fuzzy-matches on the item's display name
    /// (title) — unlike settings search, which also weights keywords and a
    /// description. Before `SearchRanker` existed, `MenuBarSearchPanel` built
    /// its `FuseProp` with no explicit weight, which defaults to `1.0`
    /// (`FuseProp(title)`). `.menuBarItem.title` must keep that exact value,
    /// otherwise adopting `SearchRanker` silently changes menu-bar-item
    /// search ranking order.
    func testMenuBarItemWeightMatchesPreRefactorFuseDefault() {
        XCTAssertEqual(SearchWeights.menuBarItem.title, 1.0)
    }

    // MARK: - Drift Guard: Settings Weighting

    /// Settings search must keep ranking a title match above a keywords
    /// match, and a keywords match above a description-only match. Lower
    /// `FuseProp` weight values contribute less to Fuse's diff score, so
    /// this asserts `title < keywords < description`.
    func testSettingsWeightsRankTitleAboveKeywordsAboveDescription() {
        let weights = SearchWeights.settings
        XCTAssertLessThan(weights.title, weights.keywords)
        XCTAssertLessThan(weights.keywords, weights.description)
    }
}
