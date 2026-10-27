//
//  SettingsURIPerDisplayTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Per-display thaw://set and thaw://toggle, announced on a private center and read back from
/// what was posted. Settings live in a throwaway suite.
@MainActor
@Suite("Settings URI per-display writes", .serialized, .scratchDefaults)
struct SettingsURIPerDisplayTests {
    /// Runs body with per-display announcements going to a private center, returning them.
    private func announced(_ body: () -> Void) -> [Notification] {
        var received: [Notification] = []
        withPrivateSettingsChangeCenter {
            let center = SettingsURIHandler.settingsChangeNotificationCenter
            let token = center.addObserver(forName: .perDisplaySettingsDidChangeViaURI, object: nil, queue: nil) {
                received.append($0)
            }
            body()
            center.removeObserver(token)
        }
        return received
    }

    /// A display that is not connected but has a saved configuration.
    private func savedDisplay() throws -> String {
        let uuid = UUID().uuidString
        try Defaults.set(
            JSONEncoder().encode([uuid: DisplayThawBarConfiguration.defaultConfiguration]),
            forKey: .displayThawBarConfigurations
        )
        return uuid
    }

    @Test("Each setting is announced with the scope its key defaults to", arguments: [
        ("useThawBar", "yes", "active", "value", "true"),
        ("alwaysShowHiddenItems", "0", "allNonThawBar", "value", "false"),
        ("thawBarLocation", "iceIcon", "allEnabled", "stringValue", "2"),
        ("thawBarLayout", "grid", "allEnabled", "stringValue", "2"),
        ("gridColumns", "6", "allEnabled", "stringValue", "6"),
    ])
    func defaultScopes(key: String, value: String, scope: String, field: String, expected: String) throws {
        let posted = announced {
            #expect(SettingsURIHandler.handleSet(key: key, value: value, sender: nil))
        }
        let info = try #require(posted.first?.userInfo)
        #expect(posted.count == 1)
        #expect(info["key"] as? String == key)
        #expect(info["scope"] as? String == scope)
        #expect(info[field].map { "\($0)" } == expected)
    }

    @Test("Columns are clamped to two through ten before they are announced", arguments: [("1", "2"), ("50", "10"), ("-3", "2")])
    func clampedColumns(value: String, expected: String) {
        let posted = announced {
            #expect(SettingsURIHandler.handleSet(key: "gridColumns", value: value, sender: nil))
        }
        #expect(posted.first?.userInfo?["stringValue"] as? String == expected)
    }

    @Test("A named display that Thaw knows is announced as that display")
    func specificDisplay() throws {
        let uuid = try savedDisplay()
        let posted = announced {
            #expect(SettingsURIHandler.handleSet(key: "useThawBar", value: "true", sender: nil, displayUUID: uuid))
            #expect(SettingsURIHandler.handleToggle(key: "alwaysShowHiddenItems", sender: nil, displayUUID: uuid))
        }
        #expect(posted.count == 2)
        #expect(posted.allSatisfy { $0.userInfo?["scope"] as? String == "specific:\(uuid)" })
        #expect(posted.last?.userInfo?["toggle"] as? Bool == true)
    }

    @Test("Toggles are announced for the two Boolean keys only")
    func toggles() {
        let posted = announced {
            #expect(SettingsURIHandler.handleToggle(key: "useThawBar", sender: nil))
            #expect(SettingsURIHandler.handleToggle(key: "alwaysShowHiddenItems", sender: nil))
            #expect(!SettingsURIHandler.handleToggle(key: "gridColumns", sender: nil))
        }
        #expect(posted.map { $0.userInfo?["scope"] as? String } == ["active", "allNonThawBar"])
        #expect(posted.allSatisfy { $0.userInfo?["toggle"] as? Bool == true && $0.userInfo?["value"] == nil })
    }

    @Test("What a link announces is what the display settings apply")
    func reachesDisplaySettings() throws {
        let uuid = try savedDisplay()
        let manager = DisplaySettingsManager()
        let posted = announced {
            _ = SettingsURIHandler.handleSet(key: "thawBarLayout", value: "vertical", sender: nil, displayUUID: uuid)
            _ = SettingsURIHandler.handleSet(key: "gridColumns", value: "8", sender: nil, displayUUID: uuid)
            _ = SettingsURIHandler.handleToggle(key: "useThawBar", sender: nil, displayUUID: uuid)
        }
        posted.forEach(manager.handleExternalPerDisplaySettingsChange)

        let config = manager.configuration(forUUID: uuid)
        #expect(config.thawBarLayout == .vertical)
        #expect(config.gridColumns == 8)
        #expect(config.useThawBar != DisplayThawBarConfiguration.defaultConfiguration.useThawBar)
    }

    @Test("A reveal names exactly one of a bundle or an item")
    func revealNeedsOneTarget() {
        let assigned: [String: MenuBarSection.Name] = ["com.example.one:Item": .hidden]
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(bundle: nil, itemID: nil, sectionAssignment: assigned) == nil)
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(bundle: "", itemID: "", sectionAssignment: assigned) == nil)
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(
            bundle: "com.example.one", itemID: "com.example.one:Item", sectionAssignment: assigned
        ) == nil)
    }

    @Test("An item ID is used as given, in its canonical form")
    func revealByItemID() {
        let identifier = "com.example.one:Item"
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(bundle: nil, itemID: identifier, sectionAssignment: [:])
            == MenuBarItemTag.canonicalPersistentIdentifier(identifier))
    }

    @Test("A bundle resolves only when exactly one of its items is assigned")
    func revealByBundle() {
        let assigned: [String: MenuBarSection.Name] = [
            "com.example.one:Item": .hidden,
            "com.example.two:First": .visible,
            "com.example.two:Second": .alwaysHidden,
            "com.example.oneplus:Item": .hidden,
        ]
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(bundle: "com.example.one", itemID: nil, sectionAssignment: assigned)
            == "com.example.one:Item")
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(bundle: "com.example.two", itemID: nil, sectionAssignment: assigned) == nil)
        #expect(SettingsURIHandler.resolveRevealItemIdentifier(bundle: "com.example.none", itemID: nil, sectionAssignment: assigned) == nil)
    }
}
