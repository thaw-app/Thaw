//
//  SortSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers the alphabetical section sort added for #936: a section's items
/// reorder by display name, localized and case-insensitive, so a crowded
/// hidden section can be made scannable without dragging each icon.
@Suite("Sort section order")
struct SortSectionOrderTests {
    private func item(_ bundleID: String, _ title: String, _ windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title),
            windowID: windowID,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
    }

    @Test("Items are sorted by the key, case-insensitive and localized")
    func sortsByKeyCaseInsensitive() {
        let items = [
            item("com.z", "Zoom", 1),
            item("com.a", "alt-tab", 2),
            item("com.b", "Bartender", 3),
            item("com.apple", "AppleScript", 4),
        ]

        let sorted = LayoutSolver.sortedSectionIdentifiers(items) { $0.tag.title }

        #expect(sorted == [
            "com.a:alt-tab",
            "com.apple:AppleScript",
            "com.b:Bartender",
            "com.z:Zoom",
        ])
    }

    @Test("Items with the same key keep their relative order (stable)")
    func sortIsStableForEqualKeys() {
        let items = [
            item("com.first", "App", 1),
            item("com.second", "App", 2),
            item("com.third", "App", 3),
        ]

        let sorted = LayoutSolver.sortedSectionIdentifiers(items) { $0.tag.title }

        #expect(sorted == ["com.first:App", "com.second:App", "com.third:App"])
    }

    @Test("An empty section sorts to empty")
    func emptySectionSortsToEmpty() {
        #expect(LayoutSolver.sortedSectionIdentifiers([]) { $0.tag.title } == [])
    }
}
