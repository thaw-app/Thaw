//
//  SavedPositionLookupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for the savedPosition lookup helpers used by
/// the position-aware restore and unmanaged-placement work.
@Suite("Saved position lookup")
struct SavedPositionLookupTests {
    // MARK: - savedPosition (exact match)

    /// An identifier present in a saved section returns its (section, index).
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

    /// An identifier present in the hidden section returns .hidden.
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

    /// An identifier not in any saved section returns nil.
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

    /// Empty savedSectionOrder returns nil.
    @Test("An empty saved section order returns nil")
    func emptySavedSectionOrder() {
        let result = LayoutSolver.savedPosition(for: "anything", in: [:])
        #expect(result == nil)
    }

    /// Multi-instance: identifier app:Status:1 matches its exact saved
    /// entry even when app:Status:0 also exists.
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

    /// An exact match wins over a baseID fallback.
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

    /// A relaunched instance with a different :N suffix finds a saved
    /// slot via baseID match.
    @Test("An instance with a drifted suffix falls back to the baseID match")
    func baseIDFallbackForInstanceDrift() {
        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status", "com.example.app:Status:1"],
        ]
        // A new instance shows up as :5 (e.g. spurious instanceIndex from
        // ordering churn). The exact match fails; baseID fallback returns
        // the first saved instance.
        let result = LayoutSolver.savedPositionByBaseID(
            for: "com.example.app:Status:5",
            in: saved
        )
        #expect(result == LayoutSolver.SavedPosition(section: .hidden, index: 0),
                "baseID fallback should return the first matching saved instance")
    }

    /// Malformed identifier with no colon never matches.
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
}
