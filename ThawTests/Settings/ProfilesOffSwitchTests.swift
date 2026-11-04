//
//  ProfilesOffSwitchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Profiles switched off must not switch on their own, whichever path asks.
@MainActor
@Suite("Automatic profile switches while Profiles is off", .scratchDefaults)
struct ProfilesOffSwitchTests {
    private func settledDisplayChange(profilesOn: Bool) throws -> (active: UUID?, profile: UUID) {
        let tmp = try ProfileTestDirectory.make(seeding: ["Docked"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appState = AppState()
        let manager = ProfileManager(profilesDirectory: tmp)
        manager.appState = appState
        let id = try #require(manager.profiles.first?.id)
        ProfilesFeature().isOn = profilesOn

        manager.applyResolvedDisplayProfile(id: id)
        return (manager.activeProfileID, id)
    }

    @Test("A settled display change doesn't switch profiles while Profiles is off")
    func displayChangeWhileOff() throws {
        #expect(try settledDisplayChange(profilesOn: false).active == nil)
    }

    @Test("A settled display change switches profiles while Profiles is on")
    func displayChangeWhileOn() throws {
        let result = try settledDisplayChange(profilesOn: true)
        #expect(result.active == result.profile)
    }
}
