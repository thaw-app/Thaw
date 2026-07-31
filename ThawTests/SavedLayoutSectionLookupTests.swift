//
//  SavedLayoutSectionLookupTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the saved-layout lookup used by the saved-order restore gate.
///
/// The live savedSectionOrder can contain several instances of the same base
/// identifier (namespace:title) split across sections, especially Control
/// Center generic items (`Item-0:1`, `Item-0:2`, ...). The divergence gate must
/// not collapse those to one base section, otherwise unrelated app-launch
/// cache churn can falsely dispatch a bulk layout apply and visually expand the
/// hidden section before restoring it.
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
