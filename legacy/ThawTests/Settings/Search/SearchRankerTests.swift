//
//  SearchRankerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Testing
@testable import Thaw

@Suite("Search ranker")
struct SearchRankerTests {
    // MARK: - Settings Weights

    /// Ifrit scales a field's diff score by `(1 - weight)` (a weight of `1`
    /// is a no-op), and a lower score ranks higher, so a larger weight ranks
    /// a field higher.
    ///
    /// Pins a regression where `SearchWeights.settings` gave `keywords` a
    /// larger weight than `title`, so keyword matches outranked title matches.
    /// Derived here rather than read from Fuse to keep the test Ifrit-free.
    private static func rankingFactor(forWeight weight: Double) -> Double {
        weight == 1 ? 1 : 1 - weight
    }

    @Test("Settings weights rank a title match above a keywords match")
    func settingsWeightsRankTitleAboveKeywords() {
        let weights = SearchWeights.settings
        let titleFactor = Self.rankingFactor(forWeight: weights.title)
        let keywordsFactor = Self.rankingFactor(forWeight: weights.keywords)
        // A smaller factor → a lower diff score → a higher rank.
        #expect(titleFactor < keywordsFactor, "title must rank above keywords")
    }

    @Test("Settings weights rank a keywords match above a description match")
    func settingsWeightsRankKeywordsAboveDescription() {
        let weights = SearchWeights.settings
        let keywordsFactor = Self.rankingFactor(forWeight: weights.keywords)
        let descriptionFactor = Self.rankingFactor(forWeight: weights.description)
        #expect(keywordsFactor < descriptionFactor, "keywords must rank above description")
    }
}
