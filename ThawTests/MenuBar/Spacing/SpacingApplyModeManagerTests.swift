//
//  SpacingApplyModeManagerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers how `SpacingApplyMode` changes what the spacing manager promises
/// to do. The mode is a user-facing switch added for the "disable the app
/// restarts" request on #1075: under `writeOnly` a spacing change must not
/// restart anything, so `willRelaunch` must report `false` even when the
/// on-disk preference would otherwise force a wave.
@MainActor
@Suite("Spacing apply mode — manager behaviour")
struct SpacingApplyModeManagerTests {
    /// The byHost global domain keys the manager reads. Mirrors the private
    /// `Key` enum so the test can plant an on-disk mismatch without shelling
    /// out to `defaults write`.
    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString
    private let anyApp = kCFPreferencesAnyApplication
    private let currentUser = kCFPreferencesCurrentUser
    private let currentHost = kCFPreferencesCurrentHost

    /// Writes `value` for both spacing keys into the byHost global domain
    /// the manager reads from, and flushes so the next `CFPreferencesCopyValue`
    /// sees it. Restored to the keys' built-in default (16) afterwards.
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

    /// Captures the original values (or nil when unset) of the two spacing
    /// keys *before* a test plants its own, and restores exactly those values
    /// afterwards, including nil for keys that were unset. Restoring the
    /// originals rather than unconditionally clearing preserves a developer's
    /// real NSStatusItemSpacing preference across the test run.
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
