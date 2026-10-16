//
//  SavedPositionLookupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Saved position lookup")
struct SavedPositionLookupTests {
    // MARK: - savedPosition (exact match)

    @Test("An identifier in the visible section returns its section and index")
    func exactMatchInVisibleSection() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status", "com.other.app:Item"],
            "hidden": ["com.example.app:Helper"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.other.app:Item",
            in: saved
        )
        #expect(result == LayoutSolver.SavedPosition(section: .visible, index: 1))
    }

    @Test("An identifier in the hidden section reports the hidden section")
    func exactMatchInHiddenSection() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
            "hidden": ["com.example.app:Helper"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.example.app:Helper",
            in: saved
        )
        #expect(result == LayoutSolver.SavedPosition(section: .hidden, index: 0))
    }

    @Test("An identifier absent from every section returns nil")
    func identifierNotFound() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.absent.app:Missing",
            in: saved
        )
        #expect(result == nil)
    }

    @Test("An empty saved section order returns nil")
    func emptySavedSectionOrder() {
        let result = LayoutSolver.savedPosition(for: "anything", in: [:])
        #expect(result == nil)
    }

    @Test("A multi-instance identifier matches its own saved entry")
    func multiInstanceExactMatch() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status", "com.example.app:Status:1", "com.example.app:Status:2"],
        ]
        let result = LayoutSolver.savedPosition(
            for: "com.example.app:Status:1",
            in: saved
        )
        #expect(result == LayoutSolver.SavedPosition(section: .visible, index: 1))
    }

    // MARK: - savedPositionByBaseID (baseID fallback)

    @Test("An exact match wins over the baseID fallback")
    func baseIDFallbackExactMatchPreferred() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status", "com.example.app:Status:1"],
        ]
        let result = LayoutSolver.savedPositionByBaseID(
            for: "com.example.app:Status:1",
            in: saved
        )
        #expect(result == LayoutSolver.SavedPosition(section: .visible, index: 1),
                "exact :1 match should win even though :0 (no suffix) shares the baseID")
    }

    @Test("An instance with a drifted suffix falls back to the baseID match")
    func baseIDFallbackForInstanceDrift() {
        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status", "com.example.app:Status:1"],
        ]
        // A new instance at :5 (instanceIndex churn) misses the exact match and gets the first saved instance.
        let result = LayoutSolver.savedPositionByBaseID(
            for: "com.example.app:Status:5",
            in: saved
        )
        #expect(result == LayoutSolver.SavedPosition(section: .hidden, index: 0),
                "baseID fallback should return the first matching saved instance")
    }

    @Test("An identifier with no colon never matches")
    func malformedIdentifierNeverMatches() {
        let saved: [String: [String]] = [
            "visible": ["com.example.app:Status"],
        ]
        let result = LayoutSolver.savedPositionByBaseID(
            for: "no-colon-here",
            in: saved
        )
        #expect(result == nil)
    }

    // MARK: - baseID(forIdentifier:) extraction contract

    /// `namespace:title` is the key for every saved-position and stale-instance lookup.
    @Test("baseID(forIdentifier:) extracts the namespace:title prefix")
    func baseIDExtractionContract() {
        // Typical multi-instance identifier: drops the trailing instanceIndex.
        #expect(LayoutSolver.baseID(forIdentifier: "com.example.app:Status:5")
            == "com.example.app:Status")
        // Long tail past maxSplits: the third component keeps its own colons.
        #expect(LayoutSolver.baseID(forIdentifier: "a:b:c:d:e") == "a:b")
        #expect(LayoutSolver.baseID(forIdentifier: "com.example.app:Status")
            == "com.example.app:Status")
        // No colon at all: split yields a single subsequence, prefix(2) keeps it.
        #expect(LayoutSolver.baseID(forIdentifier: "no-colon-here") == "no-colon-here")
        #expect(LayoutSolver.baseID(forIdentifier: "") == "")
    }
}
