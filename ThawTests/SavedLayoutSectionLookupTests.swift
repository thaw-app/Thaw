//
//  SavedLayoutSectionLookupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the saved-layout lookup used by the saved-order restore gate.
///
/// The live savedSectionOrder can contain several instances of the same base
/// identifier (namespace:title) split across sections, especially Control
/// Center generic items (`Item-0:1`, `Item-0:2`, ...). The divergence gate must
/// not collapse those to one base section, otherwise unrelated app-launch
/// cache churn can falsely dispatch a bulk layout apply and visually expand the
/// hidden section before restoring it.
final class SavedLayoutSectionLookupTests: XCTestCase {
    func testExactInstanceSectionsRemainAvailableWhenBaseIsAmbiguous() {
        let lookup = MenuBarItemManager.savedLayoutSectionLookup(savedSectionOrder: [
            "visible": ["Control Center:Item-0:1"],
            "hidden": ["Control Center:Item-0:2"],
        ])

        XCTAssertEqual(lookup.exact["Control Center:Item-0:1"], .visible)
        XCTAssertEqual(lookup.exact["Control Center:Item-0:2"], .hidden)
        XCTAssertNil(lookup.unambiguousBase["Control Center:Item-0"])
    }

    func testBaseFallbackIsAllowedWhenAllSavedInstancesShareOneSection() {
        let lookup = MenuBarItemManager.savedLayoutSectionLookup(savedSectionOrder: [
            "hidden": [
                "com.example.StatusApp:Item-0:1",
                "com.example.StatusApp:Item-0:2",
            ],
        ])

        XCTAssertEqual(lookup.unambiguousBase["com.example.StatusApp:Item-0"], .hidden)
    }

    func testDuplicateExactIdentifierAcrossSectionsIsIgnoredAsAmbiguous() {
        let lookup = MenuBarItemManager.savedLayoutSectionLookup(savedSectionOrder: [
            "visible": ["com.example.StatusApp:Item-0"],
            "hidden": ["com.example.StatusApp:Item-0"],
        ])

        XCTAssertNil(lookup.exact["com.example.StatusApp:Item-0"])
        XCTAssertNil(lookup.unambiguousBase["com.example.StatusApp:Item-0"])
    }

    func testBaseIdentifierPreservesEmptyTitles() {
        XCTAssertEqual(
            MenuBarItemManager.baseIdentifier(forSavedIdentifier: "com.apple.controlcenter::3"),
            "com.apple.controlcenter:"
        )
    }
}
