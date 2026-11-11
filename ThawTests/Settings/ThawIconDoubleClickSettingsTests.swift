//
//  ThawIconDoubleClickSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Thaw icon double-click settings", .serialized)
struct ThawIconDoubleClickSettingsTests {
    private func withScratchDefaults(_ body: () throws -> Void) throws {
        let suiteName = "ThawIconDoubleClickSettingsTests.\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suiteName))
        let previous = Defaults.store
        let previousCenter = SettingsURIHandler.settingsChangeNotificationCenter
        Defaults.store = scratch
        SettingsURIHandler.settingsChangeNotificationCenter = NotificationCenter()
        defer {
            SettingsURIHandler.settingsChangeNotificationCenter = previousCenter
            Defaults.store = previous
            scratch.removePersistentDomain(forName: suiteName)
        }
        try body()
    }

    @Test("A missing preference uses the registered true default")
    func missingPreferenceDefaultsToTrue() throws {
        try withScratchDefaults {
            Defaults.removeObject(forKey: .showAlwaysHiddenOnIconDoubleClick)

            #expect(Defaults.DefaultValue.showAlwaysHiddenOnIconDoubleClick)
            #expect(Defaults.Key.showAlwaysHiddenOnIconDoubleClick.rawValue == "ShowAlwaysHiddenOnIconDoubleClick")
            #expect(Defaults.object(forKey: .showAlwaysHiddenOnIconDoubleClick) as? Bool == true)

            let settings = AdvancedSettings()
            settings.loadInitialState()

            #expect(settings.showAlwaysHiddenOnIconDoubleClick)
        }
    }

    @Test("Disabling or re-enabling double-click reveal persists across reloads", arguments: [false, true])
    func preferencePersists(value: Bool) throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            settings.showAlwaysHiddenOnIconDoubleClick = false
            settings.showAlwaysHiddenOnIconDoubleClick = value

            #expect(Defaults.bool(forKey: .showAlwaysHiddenOnIconDoubleClick) == value)

            let reloaded = AdvancedSettings()
            reloaded.loadInitialState()

            #expect(reloaded.showAlwaysHiddenOnIconDoubleClick == value)
        }
    }

    @Test("Resetting advanced settings restores double-click reveal")
    func resetRestoresTrue() throws {
        try withScratchDefaults {
            // Prevent display settings initialization from reading the user's system spacing.
            Defaults.set(Data("{}".utf8), forKey: .displayThawBarConfigurations)
            let settings = AppSettings()
            settings.advanced.enableAlwaysHiddenSection = true
            #expect(settings.usesIconDoubleClickForAlwaysHidden)
            settings.advanced.showAlwaysHiddenOnIconDoubleClick = false
            #expect(!settings.usesIconDoubleClickForAlwaysHidden)

            settings.resetAdvanced()

            #expect(settings.advanced.showAlwaysHiddenOnIconDoubleClick)
            #expect(Defaults.bool(forKey: .showAlwaysHiddenOnIconDoubleClick))
            #expect(!settings.usesIconDoubleClickForAlwaysHidden)

            let reloaded = AdvancedSettings()
            reloaded.loadInitialState()
            #expect(reloaded.showAlwaysHiddenOnIconDoubleClick)
        }
    }

    @Test("External Boolean changes update the model and persistence", arguments: [false, true])
    func externalChangesApply(value: Bool) throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            settings.showAlwaysHiddenOnIconDoubleClick = !value

            settings.handleExternalSettingsChange(Notification(
                name: .settingsDidChangeViaURI,
                userInfo: ["key": "showAlwaysHiddenOnIconDoubleClick", "value": value]
            ))

            #expect(settings.showAlwaysHiddenOnIconDoubleClick == value)
            #expect(Defaults.bool(forKey: .showAlwaysHiddenOnIconDoubleClick) == value)
        }
    }

    @Test("Settings URIs expose a writable Boolean with the registered default")
    func uriSetAndToggle() throws {
        try withScratchDefaults {
            let key = "showAlwaysHiddenOnIconDoubleClick"
            let entry = try #require(SettingsURIHandler.keyTable[key])
            #expect(entry.defaultsKey == .showAlwaysHiddenOnIconDoubleClick)
            #expect(entry.isBoolean)
            #expect(entry.isWritable)

            #expect(SettingsURIHandler.handleToggle(key: key, sender: "com.test.App"))
            #expect(!Defaults.bool(forKey: .showAlwaysHiddenOnIconDoubleClick))

            #expect(SettingsURIHandler.handleSet(key: key, value: "true", sender: "com.test.App"))
            #expect(Defaults.bool(forKey: .showAlwaysHiddenOnIconDoubleClick))
        }
    }

    @Test("Search routes double-click reveal to the Visibility pane")
    func searchRoutesToVisibility() throws {
        let entries = SearchIndex.entries.filter {
            $0.property == .advanced("showAlwaysHiddenOnIconDoubleClick")
        }
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.pane == .visibility)
        #expect(entry.sectionText == "Reveal hidden items")
        #expect(entry.titleText == "Double-click Thaw icon")
    }
}
