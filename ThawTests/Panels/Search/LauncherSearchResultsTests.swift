//
//  LauncherSearchResultsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw
import ThawUI

@MainActor
struct LauncherSearchResultsTests {
    private typealias Item = SectionedListItem<MenuBarSearchModel.ItemID, MenuBarSearchListContent>

    @Test("Headings become the section of the rows under them, and are not rows themselves")
    func headingsFoldIntoSections() {
        let items: [Item] = [
            Item(content: .label("Recent"), id: .recentsHeader, isSelectable: false),
            Item(content: .label("Row"), id: .header(.visible), isSelectable: true),
            Item(content: .label("Menu Bar"), id: .allItemsHeader, isSelectable: false),
            Item(content: .label("Row"), id: .header(.hidden), isSelectable: true),
        ]
        let rows = LauncherSearchResults.rows(from: items)
        #expect(rows.map(\.id) == [.header(.visible), .header(.hidden)])
        #expect(rows.map(\.section) == ["Recent", "Menu Bar"])
    }

    @Test("Rows before any heading have no section")
    func rowsWithoutHeading() {
        let items: [Item] = [Item(content: .label("Row"), id: .header(.visible), isSelectable: true)]
        #expect(LauncherSearchResults.rows(from: items).map(\.section) == [nil])
    }
}
