//
//  SystemItemHidingCompatibilityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("System item hiding compatibility", .serialized)
struct SystemItemHidingCompatibilityTests {
    private func withScratchDefaults(_ body: () throws -> Void) throws {
        let suiteName = "SystemItemHidingCompatibilityTests.\(UUID().uuidString)"
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

    @Test("Enabling native hiding turns off system item hiding")
    func nativeHidingTakesPrecedence() throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            settings.enableExperimentalSystemItemHiding = true
            try #require(settings.enableExperimentalSystemItemHiding)

            settings.enableNativeAppHiding = true

            #expect(settings.enableNativeAppHiding)
            #expect(!settings.enableExperimentalSystemItemHiding)
            #expect(Defaults.bool(forKey: .enableNativeAppHiding))
            #expect(!Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("System item hiding cannot override native hiding")
    func conflictingWriteIsRejected() throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            settings.enableNativeAppHiding = true

            settings.enableExperimentalSystemItemHiding = true

            #expect(settings.enableNativeAppHiding)
            #expect(!settings.enableExperimentalSystemItemHiding)
            #expect(!Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("Disabling native hiding does not re-enable system item hiding")
    func disablingNativeHidingRequiresExplicitOptIn() throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            settings.enableExperimentalSystemItemHiding = true
            settings.enableNativeAppHiding = true
            settings.enableNativeAppHiding = false

            #expect(!settings.enableExperimentalSystemItemHiding)
            #expect(!Defaults.bool(forKey: .enableExperimentalSystemItemHiding))

            settings.enableExperimentalSystemItemHiding = true
            #expect(settings.enableExperimentalSystemItemHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("Profiles cannot enable system item hiding over native hiding", arguments: [false, true])
    func profileRespectsNativeHiding(nativeHiding: Bool) throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            settings.enableNativeAppHiding = nativeHiding
            var profile = AdvancedSettingsSnapshot.capture(from: settings)
            profile.enableExperimentalSystemItemHiding = true

            profile.apply(to: settings)

            #expect(settings.enableNativeAppHiding == nativeHiding)
            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == !nativeHiding)
        }
    }

    @Test("Restored settings give native hiding precedence", arguments: [false, true], [false, true])
    func restoreSettings(nativeHiding: Bool, systemItemHiding: Bool) throws {
        try withScratchDefaults {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)
            Defaults.set(systemItemHiding, forKey: .enableExperimentalSystemItemHiding)
            let settings = AdvancedSettings()

            settings.loadInitialState()

            let expectedSystemItemHiding = systemItemHiding && !nativeHiding
            #expect(settings.enableNativeAppHiding == nativeHiding)
            #expect(settings.enableExperimentalSystemItemHiding == expectedSystemItemHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == expectedSystemItemHiding)

            let reloaded = AdvancedSettings()
            reloaded.loadInitialState()
            #expect(reloaded.enableNativeAppHiding == nativeHiding)
            #expect(reloaded.enableExperimentalSystemItemHiding == expectedSystemItemHiding)
        }
    }

    @Test("A queued URI change cannot re-enable system item hiding")
    func queuedURIChangeRespectsCurrentMode() throws {
        try withScratchDefaults {
            let settings = AdvancedSettings()
            // URI writes precede their main-queue notification. Native hiding may start between the two.
            Defaults.set(true, forKey: .enableExperimentalSystemItemHiding)
            settings.enableNativeAppHiding = true

            settings.handleExternalSettingsChange(Notification(
                name: .settingsDidChangeViaURI,
                userInfo: ["key": "enableExperimentalSystemItemHiding", "value": true]
            ))

            #expect(settings.enableNativeAppHiding)
            #expect(!settings.enableExperimentalSystemItemHiding)
            #expect(!Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("URI set refuses the incompatible setting", arguments: [false, true])
    func uriSetRespectsNativeHiding(nativeHiding: Bool) throws {
        try withScratchDefaults {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)

            let accepted = SettingsURIHandler.handleSet(
                key: "enableExperimentalSystemItemHiding", value: "true", sender: "com.test.App"
            )

            #expect(accepted == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableNativeAppHiding) == nativeHiding)
        }
    }

    @Test("URI toggle refuses the incompatible setting", arguments: [false, true])
    func uriToggleRespectsNativeHiding(nativeHiding: Bool) throws {
        try withScratchDefaults {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)

            let accepted = SettingsURIHandler.handleToggle(
                key: "enableExperimentalSystemItemHiding", sender: "com.test.App"
            )

            #expect(accepted == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableNativeAppHiding) == nativeHiding)
        }
    }

    @Test("URI requests may still turn off an incompatible restored setting", arguments: [false, true])
    func uriCanClearConflict(toggle: Bool) throws {
        try withScratchDefaults {
            Defaults.set(true, forKey: .enableNativeAppHiding)
            Defaults.set(true, forKey: .enableExperimentalSystemItemHiding)

            let accepted = if toggle {
                SettingsURIHandler.handleToggle(key: "enableExperimentalSystemItemHiding", sender: "com.test.App")
            } else {
                SettingsURIHandler.handleSet(key: "enableExperimentalSystemItemHiding", value: "false", sender: "com.test.App")
            }

            #expect(accepted)
            #expect(!Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
            #expect(Defaults.bool(forKey: .enableNativeAppHiding))
        }
    }
}
