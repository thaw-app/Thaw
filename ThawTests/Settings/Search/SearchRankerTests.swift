//
//  SearchRankerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Testing
@testable import Thaw

@Suite("Search ranker")
struct SearchRankerTests {
    // MARK: - Settings Weights

    /// Ifrit scales a field's diff score by `(1 - weight)` (a weight of `1`
    /// is a no-op), and a lower diff score ranks the result higher. A field
    /// therefore ranks higher the *larger* its weight is.
    ///
    /// The regression these tests pin: `SearchWeights.settings` used to hand
    /// the smaller weight to `title` and the larger one to `keywords`, which
    /// — under Ifrit's "higher weight ranks higher" contract — made a keyword
    /// match outrank a title match: the opposite of the documented intent
    /// ("a title match ranks above a keywords match, which ranks above a
    /// description match"). The factor is derived here rather than read from
    /// Fuse so this stays a pure, Ifrit-free unit test.
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
