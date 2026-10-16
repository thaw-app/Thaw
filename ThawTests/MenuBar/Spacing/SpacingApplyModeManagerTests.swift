//
//  SpacingApplyModeManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// How `SpacingApplyMode` changes what the spacing manager promises. Under
/// `writeOnly` nothing restarts, so `willRelaunch` is `false` even when the
/// on-disk preference would force a wave (#1075).
@MainActor
@Suite("Spacing apply mode — manager behaviour")
struct SpacingApplyModeManagerTests {
    /// Mirrors the manager's private `Key` enum so tests can plant a mismatch
    /// without `defaults write`.
    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString
    private let anyApp = kCFPreferencesAnyApplication
    private let currentUser = kCFPreferencesCurrentUser
    private let currentHost = kCFPreferencesCurrentHost

    /// Writes both spacing keys into the byHost global domain and flushes so
    /// `CFPreferencesCopyValue` sees them.
    private func plantOnDiskSpacing(_ value: Int) {
        for key in [Self.spacingKey, Self.paddingKey] {
            CFPreferencesSetValue(
                key,
                value as CFPropertyList,
                anyApp,
                currentUser,
                currentHost
            )
        }
        CFPreferencesSynchronize(anyApp, currentUser, currentHost)
    }

    /// Restores the keys' original values, including nil, so a developer's real
    /// NSStatusItemSpacing survives the test run.
    private func restoreOriginalSpacing() {
        let keys = [Self.spacingKey, Self.paddingKey]
        let originals = keys.map { key -> (CFString, CFPropertyList?) in
            let value = CFPreferencesCopyValue(key, anyApp, currentUser, currentHost)
            return (key, value)
        }
        for (key, original) in originals {
            CFPreferencesSetValue(key, original, anyApp, currentUser, currentHost)
        }
        CFPreferencesSynchronize(anyApp, currentUser, currentHost)
    }

    @Test("willRelaunch is true under relaunchApps when on-disk differs")
    func willRelaunchTrueUnderRelaunchAppsWhenMismatch() {
        let manager = MenuBarItemSpacingManager()
        manager.offset = 4 // target spacing = 20, padding = 20
        plantOnDiskSpacing(16) // on-disk = 16 -> mismatch
        defer { restoreOriginalSpacing() }
        manager.spacingApplyMode = .relaunchApps
        #expect(manager.willRelaunch(forOffset: 4) == true)
    }

    @Test("willRelaunch is false under relaunchApps when on-disk already matches")
    func willRelaunchFalseWhenOnDiskMatches() {
        let manager = MenuBarItemSpacingManager()
        manager.offset = 4 // target = 20
        plantOnDiskSpacing(20) // on-disk = 20 -> no mismatch
        defer { restoreOriginalSpacing() }
        manager.spacingApplyMode = .relaunchApps
        #expect(manager.willRelaunch(forOffset: 4) == false)
    }

    @Test("willRelaunch is false under writeOnly even when on-disk differs")
    func willRelaunchFalseUnderWriteOnly() {
        let manager = MenuBarItemSpacingManager()
        manager.offset = 4
        plantOnDiskSpacing(16) // on-disk mismatch that would normally fire
        defer { restoreOriginalSpacing() }
        manager.spacingApplyMode = .writeOnly
        #expect(manager.willRelaunch(forOffset: 4) == false)
    }

    @Test("spacingApplyMode defaults to relaunchApps")
    func spacingApplyModeDefaultsToRelaunchApps() {
        let manager = MenuBarItemSpacingManager()
        #expect(manager.spacingApplyMode == .relaunchApps)
    }
}
