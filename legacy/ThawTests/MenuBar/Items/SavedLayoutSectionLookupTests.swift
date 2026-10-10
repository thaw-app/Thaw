//
//  SavedLayoutSectionLookupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The saved-layout lookup behind the saved-order restore gate.
///
/// savedSectionOrder can split instances of one base identifier across
/// sections (Control Center's `Item-0:1`, `Item-0:2`, ...). Collapsing them to
/// one section lets app-launch churn trigger a bulk apply that visibly expands
/// the hidden section.
@Suite("Saved layout section lookup")
struct SavedLayoutSectionLookupTests {
    @Test("Exact instance sections remain available when the base is ambiguous")
    func exactInstanceSectionsRemainAvailableWhenBaseIsAmbiguous() {
        let lookup = MenuBarItemManager.savedLayoutSectionLookup(savedSectionOrder: [
            "visible": ["Control Center:Item-0:1"],
            "hidden": ["Control Center:Item-0:2"],
        ])

        #expect(lookup.exact["Control Center:Item-0:1"] == .visible)
        #expect(lookup.exact["Control Center:Item-0:2"] == .hidden)
        #expect(lookup.unambiguousBase["Control Center:Item-0"] == nil)
    }

    @Test("The base fallback is allowed when all saved instances share one section")
    func baseFallbackIsAllowedWhenAllSavedInstancesShareOneSection() {
        let lookup = MenuBarItemManager.savedLayoutSectionLookup(savedSectionOrder: [
            "hidden": [
                "com.example.StatusApp:Item-0:1",
                "com.example.StatusApp:Item-0:2",
            ],
        ])

        #expect(lookup.unambiguousBase["com.example.StatusApp:Item-0"] == .hidden)
    }

    @Test("A duplicate exact identifier across sections is ignored as ambiguous")
    func duplicateExactIdentifierAcrossSectionsIsIgnoredAsAmbiguous() {
        let lookup = MenuBarItemManager.savedLayoutSectionLookup(savedSectionOrder: [
            "visible": ["com.example.StatusApp:Item-0"],
            "hidden": ["com.example.StatusApp:Item-0"],
        ])

        #expect(lookup.exact["com.example.StatusApp:Item-0"] == nil)
        #expect(lookup.unambiguousBase["com.example.StatusApp:Item-0"] == nil)
    }

    @Test("The base identifier preserves empty titles")
    func baseIdentifierPreservesEmptyTitles() {
        #expect(
            MenuBarItemManager.baseIdentifier(forSavedIdentifier: "com.apple.controlcenter::3")
                == "com.apple.controlcenter:"
        )
    }
}
