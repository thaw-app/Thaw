//
//  UpdateChannelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Update channels")
struct UpdateChannelTests {
    @Test("The updater starts with the app once the update question is answered, but not in the settings process")
    func startsAtLaunch() {
        #expect(UpdatesManager.startsAtLaunch(supportsSparkle: true, hasSeenConsent: true, isSettingsProcess: false))
        #expect(!UpdatesManager.startsAtLaunch(supportsSparkle: true, hasSeenConsent: false, isSettingsProcess: false))
        #expect(!UpdatesManager.startsAtLaunch(supportsSparkle: true, hasSeenConsent: true, isSettingsProcess: true))
        #expect(!UpdatesManager.startsAtLaunch(supportsSparkle: false, hasSeenConsent: true, isSettingsProcess: false))
    }

    @Test("A channel changed in the settings process checks right away; other preference changes reschedule")
    func channelChangeFromSettingsProcessChecks() {
        #expect(UpdatesManager.checksAfterStoredPreferencesChange(knownChannel: .beta, storedChannel: .alpha))
        #expect(UpdatesManager.checksAfterStoredPreferencesChange(knownChannel: .alpha, storedChannel: .beta))
        #expect(!UpdatesManager.checksAfterStoredPreferencesChange(knownChannel: .alpha, storedChannel: .alpha))
    }

    @Test("A scheduled update shows its window when Thaw is in front, or when notifications can't alert")
    func scheduledUpdateWindow() {
        #expect(UpdatesManager.showsScheduledUpdateWindow(appIsActive: true, immediateFocus: true, notificationsCanAlert: true))
        #expect(!UpdatesManager.showsScheduledUpdateWindow(appIsActive: false, immediateFocus: true, notificationsCanAlert: true))
        #expect(UpdatesManager.showsScheduledUpdateWindow(appIsActive: false, immediateFocus: false, notificationsCanAlert: false))
    }
}
