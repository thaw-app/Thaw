//
//  SettingsSearchAnchorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Every search result scrolls to a row: each row entry's id is an anchor in the panes.
@MainActor
@Suite("Settings search anchors")
struct SettingsSearchAnchorTests {
    /// Rows drawn inside ThawUI's About page, which Thaw can't mark.
    private static let unanchored: Set<String> = ["about.updateChannel", "about.replayOnboarding"]

    private static let scanned = ["Thaw/Settings/SettingsPanes", "Thaw/Panels/Appearance/Editor"]

    private static func sourceText() throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent() // Settings
            .deletingLastPathComponent() // ThawTests
            .deletingLastPathComponent() // <root>
        var text = ""
        for directory in scanned {
            let enumerator = FileManager.default.enumerator(at: root.appending(path: directory), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                text += try String(contentsOf: url, encoding: .utf8)
            }
        }
        try #require(!text.isEmpty, "pane sources not found from \(#filePath)")
        return text
    }

    private static var rowEntries: [SearchEntry] {
        SearchIndex.entries.filter { !$0.id.hasPrefix("pane.") }
    }

    @Test("Every row entry has an anchor in the panes")
    func everyRowIsAnchored() throws {
        let text = try Self.sourceText()
        let missing = Self.rowEntries.map(\.id).filter { !Self.unanchored.contains($0) && !text.contains("\"\($0)\"") }
        #expect(missing.isEmpty, "Add .settingsSearchAnchor for: \(missing.sorted())")
    }

    @Test("Every anchor names a search entry")
    func noStaleAnchors() throws {
        let text = try Self.sourceText()
        let ids = Set(SearchIndex.entries.map(\.id))
        let regex = /settingsSearchAnchor\("([^"]+)"\)/
        let stale = text.matches(of: regex).map { String($0.output.1) }.filter { !ids.contains($0) }
        #expect(stale.isEmpty, "Anchors without an entry: \(stale)")
    }

    @Test("The documented exceptions are still entries")
    func exceptionsStillExist() {
        let ids = Set(SearchIndex.entries.map(\.id))
        #expect(Self.unanchored.isSubset(of: ids))
    }

    @Test("Under Reduce Motion the flash shows and hides without animating")
    func flashRespectsReduceMotion() {
        #expect(SettingsSearchFlash.animation(reduceMotion: true, appearing: true) == nil)
        #expect(SettingsSearchFlash.animation(reduceMotion: true, appearing: false) == nil)
        #expect(SettingsSearchFlash.animation(reduceMotion: false, appearing: true) != nil)
    }

    @Test("Choosing a result requests its row; a whole page requests none, and a sidebar click clears it")
    func requestsTheRow() throws {
        let navigation = AppNavigationState()
        let row = try #require(Self.rowEntries.first { $0.pane != .general })
        var query = "x"
        SettingsSearchNavigation.selectSearchResult(row, navigationState: navigation, query: &query)
        #expect(navigation.requestedSettingsRow == row.id)
        #expect(navigation.settingsNavigationIdentifier == row.pane)
        #expect(query.isEmpty)

        SettingsSearchNavigation.selectSidebarPane(.general, navigationState: navigation)
        #expect(navigation.requestedSettingsRow == nil)

        let page = try #require(SearchIndex.entries.first { $0.id.hasPrefix("pane.") })
        SettingsSearchNavigation.selectSearchResult(page, navigationState: navigation, query: &query)
        #expect(navigation.requestedSettingsRow == nil)
    }

    @Test("A row is found by its entry id")
    func lookup() throws {
        let row = try #require(Self.rowEntries.first)
        #expect(SearchIndex.entry(withID: row.id)?.titleText == row.titleText)
        #expect(SearchIndex.entry(withID: "nowhere") == nil)
    }

    @Test("A second jump to the same row cancels the first jump's pending clear")
    func newerJumpKeepsItsHighlight() async throws {
        let navigation = AppNavigationState()
        let disarm = SettingsSearchDisarm()
        navigation.highlightedSettingsRow = "row"
        disarm.schedule("row", on: navigation, after: .milliseconds(20))
        // The second jump arms the same row again before the first clear is due.
        navigation.highlightedSettingsRow = "row"
        disarm.schedule("row", on: navigation, after: .seconds(30))
        try await Task.sleep(for: .milliseconds(300))
        #expect(navigation.highlightedSettingsRow == "row", "the first jump's clear was cancelled")
    }

    @Test("A jump's highlight clears once the flash is over")
    func highlightClears() async throws {
        let navigation = AppNavigationState()
        let disarm = SettingsSearchDisarm()
        navigation.highlightedSettingsRow = "row"
        disarm.schedule("row", on: navigation, after: .milliseconds(10))
        for _ in 0 ..< 200 where navigation.highlightedSettingsRow != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(navigation.highlightedSettingsRow == nil)
    }
}
