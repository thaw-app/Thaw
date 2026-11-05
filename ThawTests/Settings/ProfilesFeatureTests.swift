//
//  ProfilesFeatureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Profiles switch")
struct ProfilesFeatureTests {
    @Test("Profiles are on when nothing is saved, as they always were")
    func onByDefault() throws {
        try ScratchDefaults.withStore(named: "ProfilesFeatureTests") { _ in
            #expect(ProfilesFeature.isOnInDefaults)
            #expect(ProfilesFeature().isOn)
        }
    }

    @Test("Turning profiles off is saved and tells the shortcuts once")
    func switchingOffSaves() throws {
        try ScratchDefaults.withStore(named: "ProfilesFeatureTests") { _ in
            let feature = ProfilesFeature()
            var changes = 0
            feature.onChange = { changes += 1 }

            feature.isOn = false
            feature.isOn = false

            #expect(!ProfilesFeature.isOnInDefaults)
            #expect(!ProfilesFeature().isOn, "A new launch reads the saved choice")
            #expect(changes == 1, "Setting the same value again changes nothing")
        }
    }

    @Test("With profiles off, an intent says so instead of applying one")
    func intentErrorExplains() {
        let message = String(localized: ThawIntentError.profilesOff.localizedStringResource)
        #expect(message.contains("Profiles are off"))
    }
}
