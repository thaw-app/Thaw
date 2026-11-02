//
//  LayoutDetailTabTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Layout tabs")
struct LayoutDetailTabTests {
    @Test("A search result for a Layout setting opens the tab that holds it")
    func searchOpensTheRightTab() {
        // The capture button sits above the tabs, so it shows on any of them.
        let outsideTabs = ["pane.menuBarLayout", "layout.captureHiddenItems"]
        let layoutEntries = SearchIndex.entries.filter { $0.pane == .menuBarLayout && !outsideTabs.contains($0.id) }
        #expect(!layoutEntries.isEmpty)
        for entry in layoutEntries {
            #expect(LayoutDetailTab.tab(for: entry.disclosure) != nil, "\(entry.id) has no tab, so search would land on the wrong one")
        }
        #expect(LayoutDetailTab.tab(for: .layoutSpacers) == .spacers)
        #expect(LayoutDetailTab.tab(for: .layoutOptions) == .options)
        #expect(LayoutDetailTab.tab(for: .layoutAppleItems) == .appleItems)
        #expect(LayoutDetailTab.tab(for: nil) == nil)
    }

    @Test("Options first, then Groups, Spacers and Apple's items, each with its own icon")
    func tabOrder() {
        #expect(LayoutDetailTab.allCases == [.options, .groups, .spacers, .appleItems])
        #expect(Set(LayoutDetailTab.allCases.map(\.systemImage)).count == LayoutDetailTab.allCases.count)
    }
}
