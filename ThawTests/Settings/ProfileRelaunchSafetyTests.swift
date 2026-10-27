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

    @Test("A profile apply restarts apps without asking only when confirmation is off")
    func relaunchesWithoutAskingOnlyWhenConfirmationIsOff() {
        let unconfirmed = Settings(confirmRelaunch: false, applyMode: .relaunchApps)
        #expect(ProfileRelaunchSafety.relaunchesApps(requested: true, settings: unconfirmed, approved: false))
    }

    @Test("While confirmation is on, a profile apply only writes spacing until the user agrees")
    func confirmationHoldsTheRelaunch() {
        let confirmed = Settings(confirmRelaunch: true, applyMode: .relaunchApps)
        #expect(!ProfileRelaunchSafety.relaunchesApps(requested: true, settings: confirmed, approved: false))
        #expect(ProfileRelaunchSafety.relaunchesApps(requested: true, settings: confirmed, approved: true))
    }

    @Test("Write-only mode and a write-only caller never restart apps, approved or not")
    func writeOnlyNeverRelaunches() {
        let writeOnly = Settings(confirmRelaunch: false, applyMode: .writeOnly)
        #expect(!ProfileRelaunchSafety.relaunchesApps(requested: true, settings: writeOnly, approved: true))
        let relaunching = Settings(confirmRelaunch: false, applyMode: .relaunchApps)
        #expect(!ProfileRelaunchSafety.relaunchesApps(requested: false, settings: relaunching, approved: true))
    }

    @Test("Applying returns the settings it put in place", .scratchDefaults)
    func applyReturnsTheMergedSettings() throws {
        let displaySettings = DisplaySettingsManager()
        displaySettings.confirmSpacingRelaunch = false
        displaySettings.spacingApplyMode = .relaunchApps
        var profile = try JSONDecoder().decode(Profile.self, from: Data("{}".utf8))
        profile.confirmSpacingRelaunch = true

        #expect(ProfileRelaunchSafety.needsConfirmation(for: profile, displaySettings: displaySettings))
        let settings = ProfileRelaunchSafety.apply(profile, to: displaySettings)

        #expect(settings == Settings(confirmRelaunch: true, applyMode: .relaunchApps))
        #expect(displaySettings.confirmSpacingRelaunch)
    }

    @Test("A profile needs no confirmation when the user turned it off and the profile agrees", .scratchDefaults)
    func noConfirmationWhenBothOff() throws {
        let displaySettings = DisplaySettingsManager()
        displaySettings.confirmSpacingRelaunch = false
        displaySettings.spacingApplyMode = .relaunchApps
        var profile = try JSONDecoder().decode(Profile.self, from: Data("{}".utf8))
        profile.confirmSpacingRelaunch = false

        #expect(!ProfileRelaunchSafety.needsConfirmation(for: profile, displaySettings: displaySettings))
    }

    @Test("The applied spacing is the profile's entry for the menu bar's display, else its template")
    func spacingOffsetFollowsActiveDisplay() throws {
        var profile = try JSONDecoder().decode(Profile.self, from: Data("{}".utf8))
        profile.globalDisplayConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(-2)
        profile.displayConfigurations = [
            "ACTIVE": DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(5),
        ]

        #expect(ProfileRelaunchSafety.spacingOffset(of: profile, activeDisplayUUID: "ACTIVE") == 5)
        #expect(ProfileRelaunchSafety.spacingOffset(of: profile, activeDisplayUUID: "OTHER") == -2)
        #expect(ProfileRelaunchSafety.spacingOffset(of: profile, activeDisplayUUID: nil) == -2)
    }
}
