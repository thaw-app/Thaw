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

    @Test("The switch reads the opposite of native hiding as native hiding changes")
    func switchFollowsNativeHiding() throws {
        try withPrivateSettingsChangeCenter {
            let settings = AdvancedSettings()
            try #require(settings.enableExperimentalSystemItemHiding)

            settings.enableNativeAppHiding = true
            #expect(!settings.enableExperimentalSystemItemHiding)
            #expect(Defaults.bool(forKey: .enableNativeAppHiding))

            settings.enableNativeAppHiding = false
            #expect(settings.enableExperimentalSystemItemHiding)
            #expect(!Defaults.bool(forKey: .enableNativeAppHiding))
        }
    }

    @Test("Changing native hiding leaves the switch's old Defaults key alone")
    func switchIsNotStored() throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(false, forKey: .enableExperimentalSystemItemHiding)
            let settings = AdvancedSettings()

            settings.enableNativeAppHiding = true
            settings.enableNativeAppHiding = false

            #expect(settings.enableExperimentalSystemItemHiding)
            #expect(Defaults.object(forKey: .enableExperimentalSystemItemHiding) as? Bool == false)
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
        }
    }

    /// The old Standard without Apple's items and the old Everything both read as today's Standard.
    @Test("Stored settings migrate: old Standard and Everything become Standard, Native stays", arguments: [false, true], [false, true])
    func restoreSettings(nativeHiding: Bool, systemItemHiding: Bool) throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)
            Defaults.set(systemItemHiding, forKey: .enableExperimentalSystemItemHiding)
            let settings = AdvancedSettings()

            settings.loadInitialState()

            #expect(settings.enableNativeAppHiding == nativeHiding)
            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
        }
    }

    @Test("A user who never stored the switch reads the value the method needs", arguments: [false, true])
    func missingKeyIsMigrated(nativeHiding: Bool) throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)
            Defaults.removeObject(forKey: .enableExperimentalSystemItemHiding)
            let settings = AdvancedSettings()

            settings.loadInitialState()

            #expect(settings.enableExperimentalSystemItemHiding == !nativeHiding)
        }
    }

    @Test("A queued URI change for the switch changes nothing", arguments: [false, true])
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
        }
    }

    @Test("The URI reads the switch from native hiding, whatever its old key holds", arguments: [false, true])
    func uriGetReadsTheMethod(nativeHiding: Bool) async throws {
        Defaults.set(nativeHiding, forKey: .enableNativeAppHiding)
        Defaults.set(nativeHiding, forKey: .enableExperimentalSystemItemHiding)
        let capture = URIDeliveryCapture()

        let sent = await capture.run {
            SettingsURIHandler.handleGet(
                key: "enableExperimentalSystemItemHiding",
                displayUUID: nil,
                callback: "floe://thaw-response",
                broadcast: false,
                requestId: "r1",
                recipient: nil
            )
        }

        #expect(sent)
        let response = try capture.callbackResponse()
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["value"] as? Bool == !nativeHiding)
    }

    @Test("The URI cannot set the switch", arguments: [false, true])
    func uriSetIsRefused(value: Bool) throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(false, forKey: .enableNativeAppHiding)

            let accepted = SettingsURIHandler.handleSet(
                key: "enableExperimentalSystemItemHiding", value: value ? "true" : "false", sender: "com.test.App"
            )

            #expect(!accepted)
            #expect(!Defaults.bool(forKey: .enableNativeAppHiding))
        }
    }

    @Test("The URI cannot toggle the switch")
    func uriToggleIsRefused() throws {
        try withPrivateSettingsChangeCenter {
            Defaults.set(false, forKey: .enableNativeAppHiding)

            let accepted = SettingsURIHandler.handleToggle(
                key: "enableExperimentalSystemItemHiding", sender: "com.test.App"
            )

            #expect(!accepted)
            #expect(!Defaults.bool(forKey: .enableNativeAppHiding))
        }
    }
}
