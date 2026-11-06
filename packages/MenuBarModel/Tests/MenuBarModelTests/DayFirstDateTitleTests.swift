//
//  DayFirstDateTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// iStat's date and time puts the day first in some regions, so the month sits before "at".
@Suite("Day-first date titles")
struct DayFirstDateTitleTests {
    @Test("A day-first date and time keeps one identity across AM and PM and a new month")
    func dayFirstChurnCollapses() {
        let bundle = MenuBarItemTag.iStatMenusStatusBundleID
        let identifiers = Set(
            ["3 Nov at 9:41 AM", "3 Nov at 9:41 PM", "1 Dec at 12:00 AM", "30 September at 11:59 PM"]
                .map { MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\($0)") }
        )
        #expect(identifiers == ["\(bundle):# # at #:#"])
    }
}
