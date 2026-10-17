//
//  SectionedListNavigationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Sectioned list keyboard navigation")
struct SectionedListNavigationTests {
    /// A header, two rows, a header, one row.
    private let rows: [(id: String, isSelectable: Bool)] = [
        ("Visible", false), ("a", true), ("b", true), ("Hidden", false), ("c", true),
    ]

    @Test("Down and up move to the next selectable row")
    func steps() {
        #expect(SectionedListNavigation.step(from: "a", by: 1, in: rows) == "b")
        #expect(SectionedListNavigation.step(from: "b", by: -1, in: rows) == "a")
    }

    @Test("Headers are stepped over")
    func skipsHeaders() {
        #expect(SectionedListNavigation.step(from: "b", by: 1, in: rows) == "c")
        #expect(SectionedListNavigation.step(from: "c", by: -1, in: rows) == "b")
    }

    @Test("At either end the selection stays put")
    func ends() {
        #expect(SectionedListNavigation.step(from: "a", by: -1, in: rows) == "a")
        #expect(SectionedListNavigation.step(from: "c", by: 1, in: rows) == "c")
    }

    @Test("A selection that isn't in the list is left alone")
    func unknownSelection() {
        #expect(SectionedListNavigation.step(from: "z", by: 1, in: rows) == "z")
        #expect(SectionedListNavigation.step(from: nil, by: 1, in: rows) == nil)
    }
}
