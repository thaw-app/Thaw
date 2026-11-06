//
//  SearchRankerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The ordering contract of SearchRanker.sortedByRelevance(_:), shared by both
/// search surfaces. Fuzzy matching lives in Fuse.
@Suite("SearchRanker relevance sort")
struct SearchRankerTests {
    @Test("Lower diff scores rank first")
    func sortsAscendingByScore() {
        let ranked = SearchRanker.sortedByRelevance([
            (item: "worst", diffScore: 0.9),
            (item: "best", diffScore: 0.1),
            (item: "middle", diffScore: 0.5),
        ])
        #expect(ranked == ["best", "middle", "worst"])
    }

    /// The reason the sort carries an explicit tiebreak: Fuse hands back the
    /// same score for every equally good short name, so ties are routine.
    @Test("Equal scores keep their input order")
    func tiesPreserveInputOrder() {
        let tied = (0 ..< 32).map { (item: $0, diffScore: 0.42) }
        #expect(SearchRanker.sortedByRelevance(tied) == Array(0 ..< 32))
    }

    @Test("Repeated ranking of the same input gives the same order")
    func rankingIsReproducible() {
        // Interleaves ties with distinct scores so a permutation among the
        // tied members is not hidden by the surrounding order.
        let input = [
            (item: "a", diffScore: 0.2),
            (item: "b", diffScore: 0.2),
            (item: "c", diffScore: 0.1),
            (item: "d", diffScore: 0.2),
            (item: "e", diffScore: 0.1),
        ]
        let first = SearchRanker.sortedByRelevance(input)
        #expect(first == ["c", "e", "a", "b", "d"])
        for _ in 0 ..< 8 {
            #expect(SearchRanker.sortedByRelevance(input) == first)
        }
    }

    @Test("Empty input ranks to nothing")
    func emptyInput() {
        #expect(SearchRanker.sortedByRelevance([(item: Int, diffScore: Double)]()).isEmpty)
    }
}
