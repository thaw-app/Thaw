//
//  ProfilesFeatureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Profiles switched off must not switch on their own, whichever path asks.
@MainActor
@Suite("Profiles switch", .serialized, .scratchDefaults)
struct ProfilesFeatureTests {
    @Test("Profiles are on when nothing is saved, as they always were")
    func onByDefault() {
        #expect(ProfilesFeature.isOnInDefaults)
        #expect(ProfilesFeature().isOn)
    }

    @Test("Turning profiles off is saved and tells the shortcuts once")
    func switchingOffSaves() {
        let feature = ProfilesFeature()
        var changes = 0
        feature.onChange = { changes += 1 }

        feature.isOn = false
        feature.isOn = false

        #expect(!ProfilesFeature.isOnInDefaults)
        #expect(!ProfilesFeature().isOn)
        #expect(changes == 1)
    }

    @Test("With profiles off, an intent says so instead of applying one")
    func intentErrorExplains() {
        let message = String(localized: ThawIntentError.profilesOff.localizedStringResource)
        #expect(message.contains("Profiles are off"))
    }

    @Test("A settled display change switches profiles only while Profiles is on", arguments: [false, true])
    func displayChangeFollowsTheSwitch(profilesOn: Bool) throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Docked"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = AppState()
        let manager = ProfileManager(profilesDirectory: tmp)
        manager.appState = appState
        let id = try #require(manager.profiles.first?.id)
        ProfilesFeature().isOn = profilesOn

        manager.applyResolvedDisplayProfile(id: id)
        #expect(manager.activeProfileID == (profilesOn ? id : nil))
    }
}
