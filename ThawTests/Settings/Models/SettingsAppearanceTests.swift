//
//  SettingsAppearanceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// System, Light, Dark or Black for Settings and onboarding: what each choice draws, how the old black
/// background switch carries over, and the thaw:// keys, against a scratch settings store.
@MainActor
@Suite("Settings appearance", .serialized, .scratchDefaults)
struct SettingsAppearanceTests {
    // MARK: What each choice draws

    @Test("System takes macOS's look; Light holds light, Dark and Black hold dark", arguments: [
        (SettingsAppearance.system, false, SettingsWindowAppearance.light),
        (.system, true, .dark),
        (.light, true, .light),
        (.dark, false, .dark),
        (.black, false, .dark),
    ])
    func windowAppearance(choice: SettingsAppearance, macOSIsDark: Bool, expected: SettingsWindowAppearance) {
        #expect(choice.windowAppearance(macOSIsDark: macOSIsDark) == expected)
        #expect(choice.colorScheme(macOSIsDark: macOSIsDark) == (expected == .dark ? .dark : .light))
    }

    @Test("Only Black draws the settings window on black")
    func windowBackground() {
        #expect(SettingsAppearance.system.windowBackground == .system)
        #expect(SettingsAppearance.light.windowBackground == .system)
        #expect(SettingsAppearance.dark.windowBackground == .system)
        #expect(SettingsAppearance.black.windowBackground == .black)
    }

    @Test("Each choice has its own name and number")
    func names() {
        #expect(SettingsAppearance.allCases.map(\.uriName) == ["system", "light", "dark", "black"])
        #expect(SettingsAppearance.allCases.map(\.id) == [3, 0, 1, 2])
        #expect(Set(SettingsAppearance.allCases.map { String(localized: $0.localized) }).count == 4)
    }

    // MARK: Migration

    @Test("The old black background becomes Black, and no black background becomes System")
    func migration() {
        #expect(SettingsAppearance.migrated(legacyBlackBackground: true) == .black)
        #expect(SettingsAppearance.migrated(legacyBlackBackground: false) == .system)
    }

    @Test("The first read turns the old black background into Black and saves it")
    func firstReadMigratesBlack() {
        Defaults.set(true, forKey: .blackSettingsBackground)
        #expect(SettingsAppearance.stored() == .black)
        #expect(Defaults.object(forKey: .settingsAppearance) as? Int == SettingsAppearance.black.rawValue)
    }

    @Test("With no choice yet, the first read saves System")
    func firstReadSavesSystem() {
        #expect(Defaults.object(forKey: .settingsAppearance) == nil)
        #expect(SettingsAppearance.stored() == .system)
        #expect(Defaults.object(forKey: .settingsAppearance) as? Int == SettingsAppearance.system.rawValue)
    }

    @Test("A saved choice wins over the old black background")
    func savedChoiceWins() {
        Defaults.set(true, forKey: .blackSettingsBackground)
        Defaults.set(SettingsAppearance.light.rawValue, forKey: .settingsAppearance)
        #expect(SettingsAppearance.stored() == .light)
    }

    @Test("A saved number that names no choice is worked out again")
    func unreadableChoiceMigrates() {
        Defaults.set(99, forKey: .settingsAppearance)
        #expect(SettingsAppearance.stored() == .system)
        #expect(Defaults.object(forKey: .settingsAppearance) as? Int == SettingsAppearance.system.rawValue)
    }

    @Test("Loading General settings migrates and keeps the result")
    func generalSettingsLoadMigrates() {
        Defaults.set(true, forKey: .blackSettingsBackground)
        let settings = GeneralSettings()
        settings.loadInitialState()
        #expect(settings.settingsAppearance == .black)

        settings.settingsAppearance = .light
        #expect(Defaults.integer(forKey: .settingsAppearance) == SettingsAppearance.light.rawValue)
        let reloaded = GeneralSettings()
        reloaded.loadInitialState()
        #expect(reloaded.settingsAppearance == .light)
    }

    // MARK: The old switch

    @Test("The old switch on is Black; off turns only Black into System", arguments: [
        (SettingsAppearance.system, true, SettingsAppearance.black),
        (.light, true, .black),
        (.dark, true, .black),
        (.black, true, .black),
        (.light, false, .light),
        (.dark, false, .dark),
        (.system, false, .system),
        (.black, false, .system),
    ])
    func legacySwitch(current: SettingsAppearance, isBlack: Bool, expected: SettingsAppearance) {
        #expect(current.applyingLegacyBlackBackground(isBlack) == expected)
    }

    @Test("Choices parse by name, in any case, or by number", arguments: [
        ("light", SettingsAppearance.light), ("Dark", .dark), ("BLACK", .black),
        ("System", .system), ("0", .light), ("1", .dark), ("2", .black), ("3", .system),
    ])
    func parse(text: String, expected: SettingsAppearance) {
        #expect(SettingsAppearance.fromString(text) == expected)
    }

    @Test("Anything else does not parse", arguments: ["auto", "", "4", "-1", "oled"])
    func parseRefusals(text: String) {
        #expect(SettingsAppearance.fromString(text) == nil)
    }

    // MARK: thaw://

    /// Runs body with announcements going to a private center, returning what was announced.
    private func announcements(_ body: () -> Void) -> [[AnyHashable: Any]] {
        var received: [[AnyHashable: Any]] = []
        withPrivateSettingsChangeCenter {
            let center = SettingsURIHandler.settingsChangeNotificationCenter
            let token = center.addObserver(forName: .settingsDidChangeViaURI, object: nil, queue: nil) { note in
                received.append(note.userInfo ?? [:])
            }
            body()
            center.removeObserver(token)
        }
        return received
    }

    private func get(_ key: String) async throws -> [String: Any] {
        let capture = URIDeliveryCapture()
        let sent = await capture.run {
            SettingsURIHandler.handleGet(key: key, displayUUID: nil, callback: "floe://thaw-response", broadcast: false, requestId: "req", recipient: nil)
        }
        #expect(sent)
        let response = try capture.callbackResponse()
        return try #require(response["data"] as? [String: Any])
    }

    private var savedAppearance: SettingsAppearance? {
        (Defaults.object(forKey: .settingsAppearance) as? Int).flatMap(SettingsAppearance.init(rawValue:))
    }

    @Test("settingsAppearance is set by name or number and announced by number")
    func setAppearance() {
        let posted = announcements {
            #expect(SettingsURIHandler.handleSet(key: "settingsAppearance", value: "black", sender: nil))
            #expect(SettingsURIHandler.handleSet(key: "settingsAppearance", value: "0", sender: nil))
            #expect(!SettingsURIHandler.handleSet(key: "settingsAppearance", value: "auto", sender: nil))
            #expect(!SettingsURIHandler.handleToggle(key: "settingsAppearance", sender: nil))
        }
        #expect(savedAppearance == .light)
        #expect(posted.compactMap { $0["key"] as? String } == ["settingsAppearance", "settingsAppearance"])
        #expect(posted.compactMap { $0["rawEnumValue"] as? Int } == [2, 0])
    }

    @Test("The old blackSettingsBackground key still sets the appearance", arguments: [
        (SettingsAppearance.light, "true", SettingsAppearance.black),
        (.dark, "yes", .black),
        (.black, "false", .system),
        (.light, "false", .light),
        (.dark, "0", .dark),
    ])
    func setLegacyKey(current: SettingsAppearance, value: String, expected: SettingsAppearance) {
        Defaults.set(current.rawValue, forKey: .settingsAppearance)
        let posted = announcements {
            #expect(SettingsURIHandler.handleSet(key: "blackSettingsBackground", value: value, sender: nil))
        }
        #expect(savedAppearance == expected)
        #expect(posted.count == 1)
        #expect(posted.first?["key"] as? String == "settingsAppearance")
        #expect(posted.first?["rawEnumValue"] as? Int == expected.rawValue)
        #expect(Defaults.object(forKey: .blackSettingsBackground) == nil, "the old key is never written again")
    }

    @Test("Toggling the old key switches between Black and System")
    func toggleLegacyKey() {
        Defaults.set(SettingsAppearance.dark.rawValue, forKey: .settingsAppearance)
        _ = announcements {
            #expect(SettingsURIHandler.handleToggle(key: "blackSettingsBackground", sender: nil))
        }
        #expect(savedAppearance == .black)
        _ = announcements {
            #expect(SettingsURIHandler.handleToggle(key: "blackSettingsBackground", sender: nil))
        }
        #expect(savedAppearance == .system)
    }

    @Test("Reading reports the appearance by name, and the old key as whether it is Black")
    func getAppearance() async throws {
        Defaults.set(SettingsAppearance.black.rawValue, forKey: .settingsAppearance)
        let appearance = try await get("settingsAppearance")
        #expect(appearance["value"] as? String == "black")
        #expect(appearance["rawValue"] as? Int == 2)
        #expect(appearance["type"] as? String == "enum")
        #expect(appearance["validValues"] as? [String: Int] == ["system": 3, "light": 0, "dark": 1, "black": 2])
        #expect(try await get("blackSettingsBackground")["value"] as? Bool == true)

        Defaults.set(SettingsAppearance.light.rawValue, forKey: .settingsAppearance)
        #expect(try await get("settingsAppearance")["value"] as? String == "light")
        #expect(try await get("blackSettingsBackground")["value"] as? Bool == false)
    }
}
