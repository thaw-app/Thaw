//
//  WhatsNewUpgradeGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Opening What's New after an update", .serialized, .scratchDefaults)
struct WhatsNewUpgradeGateTests {
    @Test("A first launch records the version and opens nothing")
    func firstLaunch() {
        Defaults.removeObject(forKey: .lastWhatsNewVersion)
        #expect(!WhatsNewUpgradeGate.recordVersion("3.0", opensAfterUpdate: true))
        #expect(Defaults.string(forKey: .lastWhatsNewVersion) == "3.0")
    }

    @Test("An update opens What's New once")
    func updateOpensOnce() {
        Defaults.set("2.9", forKey: .lastWhatsNewVersion)
        #expect(WhatsNewUpgradeGate.recordVersion("3.0", opensAfterUpdate: true))
        #expect(!WhatsNewUpgradeGate.recordVersion("3.0", opensAfterUpdate: true))
    }

    @Test("With the setting off an update records the version without opening, so turning it on later replays nothing")
    func settingOffRecordsSilently() {
        Defaults.set("2.9", forKey: .lastWhatsNewVersion)
        #expect(!WhatsNewUpgradeGate.recordVersion("3.0", opensAfterUpdate: false))
        #expect(Defaults.string(forKey: .lastWhatsNewVersion) == "3.0")
        #expect(!WhatsNewUpgradeGate.recordVersion("3.0", opensAfterUpdate: true))
    }

    @Test("The stored release notes switches read the saved values, not the unloaded Privacy model")
    func storedSwitchesFollowTheStore() {
        Defaults.removeObject(forKey: .showReleaseNotesAfterUpdate)
        Defaults.removeObject(forKey: .fetchReleaseNotes)
        #expect(AppState.storedShowReleaseNotesAfterUpdate)
        #expect(AppState.storedFetchReleaseNotes)

        Defaults.set(false, forKey: .showReleaseNotesAfterUpdate)
        Defaults.set(false, forKey: .fetchReleaseNotes)
        #expect(!AppState.storedShowReleaseNotesAfterUpdate)
        #expect(!AppState.storedFetchReleaseNotes)
    }
}
