//
//  AutomationSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the whitelist bookkeeping in ``AutomationSettings``.
///
/// The whitelist lives in `UserDefaults` via `SettingsURIHandler`, so each
/// case runs in `withScratchDefaults` against a throwaway, empty store.
@MainActor
@Suite("Automation settings", .serialized)
struct AutomationSettingsTests {
    // MARK: Bundle ID validation

    @Test("A dotted, space-free bundle ID is valid")
    func wellFormedBundleIDIsValid() {
        #expect(AutomationSettings.isValidBundleId("com.example.App"))
    }

    @Test(
        "A bundle ID without a dot, with a space, or empty is rejected",
        arguments: ["Example", "com example App", "", "   "]
    )
    func malformedBundleIDIsRejected(_ candidate: String) {
        #expect(!AutomationSettings.isValidBundleId(candidate))
    }

    @Test("Surrounding whitespace does not make a valid bundle ID invalid")
    func bundleIDValidationTrimsWhitespace() {
        #expect(AutomationSettings.isValidBundleId("  com.example.App  "))
    }

    // MARK: Whitelist

    @Test("An added bundle ID appears in the whitelist")
    func addingABundleIDWhitelistsIt() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.addToWhitelist(bundleId: "com.example.Alpha")

            #expect(settings.whitelistedApps.map(\.bundleId) == ["com.example.Alpha"])
        }
    }

    @Test("A blank bundle ID is not added")
    func blankBundleIDIsIgnored() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.addToWhitelist(bundleId: "   \n")

            #expect(settings.whitelistedApps.isEmpty)
        }
    }

    @Test("An added bundle ID is stored trimmed")
    func addedBundleIDIsTrimmed() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.addToWhitelist(bundleId: "  com.example.Alpha  ")

            #expect(settings.whitelistedApps.map(\.bundleId) == ["com.example.Alpha"])
        }
    }

    @Test("Removing a bundle ID drops it from the whitelist")
    func removingABundleIDDropsIt() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.addToWhitelist(bundleId: "com.example.Alpha")
            settings.addToWhitelist(bundleId: "com.example.Beta")

            settings.removeFromWhitelist(bundleId: "com.example.Alpha")

            #expect(settings.whitelistedApps.map(\.bundleId) == ["com.example.Beta"])
        }
    }

    @Test("Entries are ordered by display name, not insertion order")
    func whitelistIsSortedByDisplayName() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            for id in ["com.example.Zulu", "com.example.Alpha", "com.example.Mike"] {
                settings.addToWhitelist(bundleId: id)
            }

            #expect(settings.whitelistedApps.map(\.bundleId) == [
                "com.example.Alpha",
                "com.example.Mike",
                "com.example.Zulu",
            ])
        }
    }

    @Test("An unresolvable bundle ID displays as itself")
    func unknownAppDisplaysItsBundleID() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.addToWhitelist(bundleId: "com.example.NotInstalled")

            let app = settings.whitelistedApps.first
            #expect(app?.displayName == "com.example.NotInstalled")
        }
    }

    @Test("Whitelisted apps compare by bundle ID alone")
    func whitelistedAppEqualityUsesBundleID() {
        let lhs = AutomationSettings.WhitelistedApp(bundleId: "com.example.App", appName: "One", icon: nil)
        let rhs = AutomationSettings.WhitelistedApp(bundleId: "com.example.App", appName: "Two", icon: nil)
        let other = AutomationSettings.WhitelistedApp(bundleId: "com.example.Other", appName: "One", icon: nil)

        #expect(lhs == rhs)
        #expect(lhs != other)
        #expect(lhs.id == "com.example.App")
    }

    @Test("The enabled flag round-trips through Defaults")
    func enabledFlagPersists() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.isSettingsURIEnabled = true
            #expect(Defaults.bool(forKey: .settingsURIEnabled))

            settings.isSettingsURIEnabled = false
            #expect(!Defaults.bool(forKey: .settingsURIEnabled))
        }
    }

    @Test("Adding the current app whitelists this bundle")
    func addCurrentAppWhitelistsThisBundle() throws {
        try withScratchDefaults { _ in
            let bundleID = try #require(
                Bundle.main.bundleIdentifier,
                "the test host is an app bundle, so it always has an identifier"
            )
            let settings = AutomationSettings()
            #expect(settings.whitelistedApps.isEmpty)

            settings.addCurrentApp()

            #expect(settings.whitelistedApps.contains { $0.bundleId == bundleID })
            #expect(SettingsURIHandler.getWhitelist().contains(bundleID))
        }
    }

    @Test("Adding the current app twice does not duplicate the entry")
    func addCurrentAppIsIdempotent() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()

            settings.addCurrentApp()
            settings.addCurrentApp()

            #expect(settings.whitelistedApps.count == 1)
        }
    }
}
