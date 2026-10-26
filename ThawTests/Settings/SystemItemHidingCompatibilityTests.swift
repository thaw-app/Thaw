//
//  SystemItemHidingCompatibilityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Standard always hides Apple's items too, so the Apple-items switch is on exactly when native hiding is off.
@MainActor
@Suite("System item hiding follows the hiding method", .serialized, .scratchDefaults)
struct SystemItemHidingCompatibilityTests {
    @Test("Fresh settings use Standard, which hides Apple's items")
    func freshSettingsHideAppleItems() {
        let settings = AdvancedSettings()
        #expect(!settings.enableNativeAppHiding)
        #expect(settings.enableExperimentalSystemItemHiding)
    }

    @Test("Enabling native hiding turns off system item hiding")
    func nativeHidingTakesPrecedence() throws {
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()
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
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()
            settings.enableNativeAppHiding = true

            settings.enableExperimentalSystemItemHiding = true

            #expect(settings.enableNativeAppHiding)
            #expect(!settings.enableExperimentalSystemItemHiding)
            #expect(!Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("Leaving native hiding goes back to Standard with Apple's items")
    func disablingNativeHidingRestoresStandard() throws {
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()
            settings.enableNativeAppHiding = true
            settings.enableNativeAppHiding = false

            #expect(settings.enableExperimentalSystemItemHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("Standard cannot be turned into the old Standard without Apple's items")
    func standardKeepsAppleItems() throws {
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()

            settings.enableExperimentalSystemItemHiding = false

            #expect(settings.enableExperimentalSystemItemHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("A profile saved with the switch loads, and applying it keeps what the method needs", arguments: [false, true], [false, true])
    func profileFollowsTheMethod(nativeHiding: Bool, storedSystemItemHiding: Bool) throws {
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()
            settings.enableNativeAppHiding = nativeHiding
            let json = Data(#"{"enableExperimentalSystemItemHiding": \#(storedSystemItemHiding)}"#.utf8)
            let profile = try JSONDecoder().decode(AdvancedSettingsSnapshot.self, from: json)

            profile.apply(to: settings)

            #expect(settings.enableNativeAppHiding == nativeHiding)
            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == !nativeHiding)
        }
    }

    @Test("Stored settings migrate: old Standard and Everything become Standard, Native stays", arguments: [false, true], [false, true])
    func restoreSettings(nativeHiding: Bool, systemItemHiding: Bool) throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)
            Defaults.set(systemItemHiding, forKey: .enableExperimentalSystemItemHiding)
            let settings = AdvancedSettings()

            settings.loadInitialState()

            #expect(settings.enableNativeAppHiding == nativeHiding)
            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == !nativeHiding)

            let reloaded = AdvancedSettings()
            reloaded.loadInitialState()
            #expect(reloaded.enableNativeAppHiding == nativeHiding)
            #expect(reloaded.enableExperimentalSystemItemHiding == !nativeHiding)
        }
    }

    @Test("A user who never stored the switch reads the value the method needs, in settings and in Defaults", arguments: [false, true])
    func missingKeyIsMigrated(nativeHiding: Bool) throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)
            Defaults.removeObject(forKey: .enableExperimentalSystemItemHiding)
            let settings = AdvancedSettings()

            settings.loadInitialState()

            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
            #expect(Defaults.object(forKey: .enableExperimentalSystemItemHiding) as? Bool == !nativeHiding)
        }
    }

    @Test("A queued URI change cannot change what the method needs", arguments: [false, true])
    func queuedURIChangeRespectsCurrentMode(nativeHiding: Bool) throws {
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()
            settings.enableNativeAppHiding = nativeHiding

            settings.handleExternalSettingsChange(Notification(
                name: .settingsDidChangeViaURI,
                userInfo: ["key": "enableExperimentalSystemItemHiding", "value": nativeHiding]
            ))

            #expect(settings.enableNativeAppHiding == nativeHiding)
            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding) == !nativeHiding)
        }
    }

    @Test("The URI can read the switch but not set it", arguments: [false, true])
    func uriSetIsRefused(value: Bool) throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(true, forKey: .enableExperimentalSystemItemHiding)

            let accepted = SettingsURIHandler.handleSet(
                key: "enableExperimentalSystemItemHiding", value: value ? "true" : "false", sender: "com.test.App"
            )

            #expect(!accepted)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }

    @Test("The URI cannot toggle the switch")
    func uriToggleIsRefused() throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(true, forKey: .enableExperimentalSystemItemHiding)

            let accepted = SettingsURIHandler.handleToggle(
                key: "enableExperimentalSystemItemHiding", sender: "com.test.App"
            )

            #expect(!accepted)
            #expect(Defaults.bool(forKey: .enableExperimentalSystemItemHiding))
        }
    }
}
