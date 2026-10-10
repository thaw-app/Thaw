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
    /// Runs body with Defaults pointed at an empty, throwaway suite.
    private func withScratchDefaults<T>(_ body: () throws -> T) throws -> T {
        let suiteName = "SpacingApplyModeTests.\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suiteName))
        let previous = Defaults.store
        Defaults.store = scratch
        defer {
            Defaults.store = previous
            scratch.removePersistentDomain(forName: suiteName)
        }
        return try body()
    }

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

    // MARK: Persistence

    @Test("The mode is saved on change and read back by a new manager")
    func modePersists() throws {
        try withScratchDefaults {
            let writer = DisplaySettingsManager()
            #expect(writer.spacingApplyMode == .relaunchApps)
            writer.spacingApplyMode = .writeOnly
            #expect(Defaults.string(forKey: .spacingApplyMode) == SpacingApplyMode.writeOnly.rawValue)

            #expect(DisplaySettingsManager().spacingApplyMode == .writeOnly)
        }
    }

    @Test("An unknown saved value falls back to relaunching apps")
    func unknownSavedValueFallsBack() throws {
        try withScratchDefaults {
            Defaults.set("not-a-real-mode", forKey: .spacingApplyMode)
            #expect(DisplaySettingsManager().spacingApplyMode == .relaunchApps)
        }
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
