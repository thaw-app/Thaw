//
//  MenuBarSearchAnnouncementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Search VoiceOver announcements", .serialized, .scratchDefaults)
struct MenuBarSearchAnnouncementTests {
    private typealias World = LayoutEditorWorld

    private func result(_ title: String, section: String?) -> MenuBarSearchResult {
        let item = World.item(title)
        Defaults.set([item.uniqueIdentifier: title], forKey: .menuBarItemCustomNames)
        return MenuBarSearchResult(item: item, ownerName: nil, section: section)
    }

    @Test("A row is read with its section, and alone without one")
    func row() {
        #expect(MenuBarSearchAnnouncement.row(result("Alpha", section: "Hidden")) == "Alpha, Hidden")
        #expect(MenuBarSearchAnnouncement.row(result("Alpha", section: nil)) == "Alpha")
    }

    @Test("Results are read as a count and the first match")
    func results() {
        let alpha = result("Alpha", section: nil)
        #expect(MenuBarSearchAnnouncement.results([alpha]) == "1 result. Alpha")
        #expect(MenuBarSearchAnnouncement.results([alpha, alpha]) == "2 results. Alpha")
        #expect(MenuBarSearchAnnouncement.results([]) == "0 results")
    }
}
