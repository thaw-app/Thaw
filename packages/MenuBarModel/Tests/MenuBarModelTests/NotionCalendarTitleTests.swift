//
//  NotionCalendarTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// Notion Calendar has one menu bar item whose title is the next event and its countdown, or nothing.
@Suite("Notion Calendar titles")
struct NotionCalendarTitleTests {
    @Test(
        "Every Notion Calendar title names the same item",
        arguments: ["🤸🏻Sara gymnastics · 13 m left", "🤸🏻Sara gymnastics · 1 m left", "Standup · 5 m left", "Item-0"]
    )
    func everyTitleCollapses(title: String) {
        let bundle = "com.cron.electron"
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\(title)") == "\(bundle):Item")
        #expect(MenuBarItemTag(namespace: .string(bundle), title: title).tagIdentifier == "\(bundle):Item")
    }
}
