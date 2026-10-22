//
//  ProfileRelaunchSafetyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Applying a profile may make spacing relaunches safer, never less safe.
@MainActor
@Suite("Profile relaunch safety", .serialized)
struct ProfileRelaunchSafetyTests {
    private typealias Settings = ProfileRelaunchSafety.Settings

    @Test("A profile saved without confirmation keeps the user's confirmation on")
    func keepsConfirmationOn() {
        let merged = ProfileRelaunchSafety.merged(
            current: Settings(confirmRelaunch: true, applyMode: .relaunchApps),
            profileConfirmRelaunch: false,
            profileApplyMode: .relaunchApps
        )
        #expect(merged.confirmRelaunch)
    }

    @Test("A profile saved with confirmation turns it on")
    func turnsConfirmationOn() {
        let merged = ProfileRelaunchSafety.merged(
            current: Settings(confirmRelaunch: false, applyMode: .relaunchApps),
            profileConfirmRelaunch: true,
            profileApplyMode: nil
        )
        #expect(merged.confirmRelaunch)
    }

    @Test("Confirmation stays off only when the user and the profile both turned it off")
    func confirmationOffOnlyWhenBothOff() {
        let merged = ProfileRelaunchSafety.merged(
            current: Settings(confirmRelaunch: false, applyMode: .relaunchApps),
            profileConfirmRelaunch: false,
            profileApplyMode: .relaunchApps
        )
        #expect(!merged.confirmRelaunch)
    }

    @Test("A profile saved with relaunching keeps the user's write-only mode")
    func keepsWriteOnly() {
        let merged = ProfileRelaunchSafety.merged(
            current: Settings(confirmRelaunch: true, applyMode: .writeOnly),
            profileConfirmRelaunch: true,
            profileApplyMode: .relaunchApps
        )
        #expect(merged.applyMode == .writeOnly)
    }

    @Test("A profile saved with write-only mode turns it on")
    func turnsWriteOnlyOn() {
        let merged = ProfileRelaunchSafety.merged(
            current: Settings(confirmRelaunch: true, applyMode: .relaunchApps),
            profileConfirmRelaunch: true,
            profileApplyMode: .writeOnly
        )
        #expect(merged.applyMode == .writeOnly)
    }

    @Test("Applying an old profile leaves the user's safer settings in place", .scratchDefaults)
    func applyKeepsSaferSettings() throws {
        let displaySettings = DisplaySettingsManager()
        displaySettings.confirmSpacingRelaunch = true
        displaySettings.spacingApplyMode = .writeOnly
        var profile = try JSONDecoder().decode(Profile.self, from: Data("{}".utf8))
        profile.confirmSpacingRelaunch = false
        profile.spacingApplyMode = .relaunchApps

        ProfileRelaunchSafety.apply(profile, to: displaySettings)

        #expect(displaySettings.confirmSpacingRelaunch)
        #expect(displaySettings.spacingApplyMode == .writeOnly)
    }

    @Test("A profile without a saved mode keeps the user's mode")
    func keepsModeWhenProfileHasNone() {
        let merged = ProfileRelaunchSafety.merged(
            current: Settings(confirmRelaunch: true, applyMode: .relaunchApps),
            profileConfirmRelaunch: true,
            profileApplyMode: nil
        )
        #expect(merged.applyMode == .relaunchApps)
    }
}
