//
//  SpacingApplyModeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Write-only mode must never relaunch apps or ask about relaunching them (#1230).
@MainActor
@Suite("Spacing apply mode", .serialized)
struct SpacingApplyModeTests {
    /// An offset whose target differs from the real on-disk spacing. Read-only,
    /// so the tester's NSStatusItemSpacing is never written.
    private func offsetNotOnDisk() -> Int {
        let onDisk = CFPreferencesCopyValue(
            "NSStatusItemSpacing" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int ?? 16
        return onDisk - 16 == 2 ? 4 : 2
    }

    // MARK: Mode

    @Test("Round-trips through its raw value and JSON")
    func modeRoundTrips() throws {
        #expect(SpacingApplyMode.allCases == [.relaunchApps, .writeOnly])
        for mode in SpacingApplyMode.allCases {
            #expect(SpacingApplyMode(rawValue: mode.rawValue) == mode)
            let data = try JSONEncoder().encode(mode)
            #expect(try JSONDecoder().decode(SpacingApplyMode.self, from: data) == mode)
        }
    }

    // MARK: Spacing manager

    @Test("The spacing manager relaunches apps by default")
    func managerDefaultsToRelaunchApps() {
        #expect(MenuBarItemSpacingManager().spacingApplyMode == .relaunchApps)
        #expect(Defaults.DefaultValue.spacingApplyMode == .relaunchApps)
    }

    @Test("Write-only mode refuses every relaunch request", arguments: [false, true])
    func writeOnlyNeverRelaunches(requested: Bool) {
        #expect(!MenuBarItemSpacingManager.mayRelaunchApps(mode: .writeOnly, requested: requested))
    }

    @Test("Relaunch mode follows the caller's request", arguments: [false, true])
    func relaunchModeFollowsTheRequest(requested: Bool) {
        #expect(MenuBarItemSpacingManager.mayRelaunchApps(mode: .relaunchApps, requested: requested) == requested)
    }

    @Test("A spacing that differs from disk relaunches only in relaunch mode")
    func willRelaunchHonorsTheMode() {
        let manager = MenuBarItemSpacingManager()
        let offset = offsetNotOnDisk()
        #expect(!manager.isOnDisk(offset: offset))

        manager.spacingApplyMode = .relaunchApps
        #expect(manager.willRelaunch(forOffset: offset))

        manager.spacingApplyMode = .writeOnly
        #expect(!manager.willRelaunch(forOffset: offset))
        #expect(!manager.isOnDisk(offset: offset), "The mode changes what happens, not what is on disk")
    }

    // MARK: Confirmation

    @Test("Write-only mode never asks, whatever the confirmation toggle says", arguments: [false, true])
    func writeOnlyNeverConfirms(confirmationsEnabled: Bool) {
        #expect(!DisplaySettingsManager.needsSpacingRelaunchConfirmation(
            applyMode: .writeOnly,
            confirmationsEnabled: confirmationsEnabled
        ))
    }

    @Test("Relaunch mode asks exactly when confirmations are on", arguments: [false, true])
    func relaunchModeFollowsTheToggle(confirmationsEnabled: Bool) {
        #expect(DisplaySettingsManager.needsSpacingRelaunchConfirmation(
            applyMode: .relaunchApps,
            confirmationsEnabled: confirmationsEnabled
        ) == confirmationsEnabled)
    }

    // MARK: Relaunch on display changes

    @Test("A display change never relaunches apps, a spacing edit does")
    func onlySpacingEditsRelaunch() {
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: "screenParametersChanged"))
        #expect(DisplaySettingsManager.spacingApplyRelaunchesApps(reason: "configurationsChanged"))
        #expect(DisplaySettingsManager.spacingApplyRelaunchesApps(reason: "userReapply"))
    }

    @Test("Seeding a newly connected display's configuration never relaunches apps")
    func seedingANewDisplayNeverRelaunches() {
        let seeded = DisplaySettingsManager.configurationsChangeReason(writeOnlyReason: "displaySeeded")
        let edited = DisplaySettingsManager.configurationsChangeReason(writeOnlyReason: nil)
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: seeded))
        #expect(DisplaySettingsManager.spacingApplyRelaunchesApps(reason: edited))
    }

    @Test("A thaw:// link's spacing never relaunches apps while a relaunch needs confirming")
    func linkSpacingWaitsForConfirmation() {
        let unconfirmed = DisplaySettingsManager.configurationsChangeReason(
            writeOnlyReason: DisplaySettingsManager.linkWriteOnlyReason(confirmRelaunch: true)
        )
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: unconfirmed))

        // With the confirmation turned off the person has agreed to relaunches, and a link behaves like an edit.
        let agreed = DisplaySettingsManager.configurationsChangeReason(
            writeOnlyReason: DisplaySettingsManager.linkWriteOnlyReason(confirmRelaunch: false)
        )
        #expect(DisplaySettingsManager.spacingApplyRelaunchesApps(reason: agreed))
    }

    @Test("A profile a display change switches to writes its spacing without relaunching apps")
    func displayProfileSwitchNeverRelaunches() {
        let reason = DisplaySettingsManager.configurationsChangeReason(writeOnlyReason: DisplaySettingsManager.displayProfileSwitchReason)
        #expect(reason == "displayProfileSwitch")
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: reason))
    }

    @Test("Assigning a profile's configurations write-only leaves later edits free to relaunch", arguments: [false, true])
    func writeOnlyAssignmentIsScoped(writeOnly: Bool) {
        let manager = DisplaySettingsManager()
        manager.assignConfigurations(["display": .defaultConfiguration], writeOnly: writeOnly)
        #expect(manager.configurations["display"] == .defaultConfiguration)
        #expect(manager.writeOnlyConfigurationsReason == nil)
    }

    // MARK: Persistence

    @Test("The mode is saved on change and read back by a new manager", .scratchDefaults)
    func modePersists() throws {
        let writer = DisplaySettingsManager()
        #expect(writer.spacingApplyMode == .relaunchApps)
        writer.spacingApplyMode = .writeOnly
        #expect(Defaults.string(forKey: .spacingApplyMode) == SpacingApplyMode.writeOnly.rawValue)

        #expect(DisplaySettingsManager().spacingApplyMode == .writeOnly)
    }

    @Test("Don't ask again on Apply turns confirmations off", .scratchDefaults)
    func suppressedApplyDisablesConfirmations() throws {
        let manager = DisplaySettingsManager()
        manager.rememberSpacingRelaunchAnswer(approved: true)

        #expect(!manager.confirmSpacingRelaunch)
        #expect(manager.spacingApplyMode == .relaunchApps)
    }

    @Test("Don't ask again on Cancel stops relaunching, so the prompt stays away", .scratchDefaults)
    func suppressedCancelStopsRelaunching() throws {
        let manager = DisplaySettingsManager()
        manager.rememberSpacingRelaunchAnswer(approved: false)

        #expect(manager.spacingApplyMode == .writeOnly)
        #expect(manager.confirmSpacingRelaunch, "a decline must never allow an unasked relaunch")
        #expect(DisplaySettingsManager().spacingApplyMode == .writeOnly)
    }

    @Test("An unknown saved value falls back to relaunching apps", .scratchDefaults)
    func unknownSavedValueFallsBack() throws {
        Defaults.set("not-a-real-mode", forKey: .spacingApplyMode)
        #expect(DisplaySettingsManager().spacingApplyMode == .relaunchApps)
    }

    // MARK: Profiles

    @Test("A profile saved before the setting existed carries no mode")
    func olderProfileHasNoMode() throws {
        let profile = try JSONDecoder().decode(Profile.self, from: Data("{}".utf8))
        #expect(profile.spacingApplyMode == nil)
    }

    @Test("A profile keeps its mode through encoding")
    func profileRoundTripsTheMode() throws {
        var profile = try JSONDecoder().decode(Profile.self, from: Data("{}".utf8))
        profile.spacingApplyMode = .writeOnly
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        #expect(decoded.spacingApplyMode == .writeOnly)
        #expect(decoded.content.spacingApplyMode == .writeOnly)
    }

    // MARK: Search

    @Test("Settings search finds the setting on the Displays page")
    func searchEntryExists() throws {
        let entry = try #require(SearchIndex.entries.first { $0.id == "displays.spacingApplyMode" })
        #expect(entry.pane == .displays)
    }
}

@Suite("Spacing apply choice")
struct SpacingApplyChoiceTests {
    @Test("The stored settings read back as one choice")
    func reads() {
        #expect(SpacingApplyChoice(mode: .relaunchApps, confirms: true) == .askFirst)
        #expect(SpacingApplyChoice(mode: .relaunchApps, confirms: false) == .relaunchNow)
        #expect(SpacingApplyChoice(mode: .writeOnly, confirms: true) == .waitForRestart)
        #expect(SpacingApplyChoice(mode: .writeOnly, confirms: false) == .waitForRestart)
    }

    @Test("Each choice writes back the settings it was read from", arguments: SpacingApplyChoice.allCases)
    func roundTrip(choice: SpacingApplyChoice) {
        let confirms = choice.confirms ?? true
        #expect(SpacingApplyChoice(mode: choice.mode, confirms: confirms) == choice)
    }

    @Test("Waiting for a restart leaves the confirmation switch alone")
    func waitingKeepsSwitch() {
        #expect(SpacingApplyChoice.waitForRestart.confirms == nil)
        #expect(SpacingApplyChoice.waitForRestart.mode == .writeOnly)
    }

    @Test("The restarting choices warn that unsaved work may be lost", arguments: [SpacingApplyChoice.askFirst, .relaunchNow])
    func restartingNoticeWarns(choice: SpacingApplyChoice) {
        let message = String(localized: choice.relaunchNotice.message)
        #expect(message.contains("every app with a menu bar item"))
        #expect(message.contains("unsaved work"))
        #expect(message.contains("Connecting or disconnecting a display only saves"))
    }

    @Test("Restarting right away says it doesn't ask and can happen again with each profile")
    func relaunchNowNoticeSaysItRepeats() {
        let message = String(localized: SpacingApplyChoice.relaunchNow.relaunchNotice.message)
        #expect(message.contains("doesn’t ask first"))
        #expect(message.contains("each time a profile with different spacing is applied"))
    }

    @Test("Waiting promises no restart")
    func waitingNoticeRestartsNothing() {
        let notice = SpacingApplyChoice.waitForRestart.relaunchNotice
        #expect(String(localized: notice.message).contains("without restarting any app"))
        #expect(!String(localized: notice.message).contains("unsaved"))
    }
}
