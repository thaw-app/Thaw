//
//  AutomationSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``AutomationSettings``' whitelist bookkeeping — the part of the
/// Settings URI automation surface that is real logic rather than view code.
///
/// The whitelist lives in `UserDefaults` through `SettingsURIHandler`, so
/// every case that touches it runs inside `withScratchDefaults`: the model
/// reads and writes a throwaway store instead of the developer's own
/// automation settings, and each case starts from an empty domain.
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

    @Test("Removing by index drops exactly the selected rows")
    func removingByIndexDropsTheSelectedRows() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            for id in ["com.example.Alpha", "com.example.Beta", "com.example.Gamma"] {
                settings.addToWhitelist(bundleId: id)
            }
            // Sorted by display name, so the order here is alpha, beta, gamma.
            #expect(settings.whitelistedApps.count == 3)

            settings.removeWhitelistedApp(at: IndexSet([0, 2]))

            #expect(settings.whitelistedApps.map(\.bundleId) == ["com.example.Beta"])
        }
    }

    @Test("An out-of-range index is skipped rather than trapping")
    func outOfRangeIndexIsSkipped() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()
            settings.addToWhitelist(bundleId: "com.example.Alpha")

            settings.removeWhitelistedApp(at: IndexSet([5]))

            #expect(settings.whitelistedApps.map(\.bundleId) == ["com.example.Alpha"])
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
}
