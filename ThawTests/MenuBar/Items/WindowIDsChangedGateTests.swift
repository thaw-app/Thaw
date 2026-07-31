//
//  WindowIDsChangedGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the windowID-change gate that decides whether a cache cycle
/// should dispatch a saved-layout re-apply.
///
/// The gate fires when a previously-seen window has disappeared (an item quit
/// or relaunched). The bug: with "Displays have separate Spaces" enabled, when
/// the menu bar follows the user's focus to another display the previous
/// display's item windows leave the active-space window list, so they read as
/// "missing" and the gate fires a full bulk re-sort on every cross-screen
/// focus change. That re-sort is what thrashed the control items and drifted
/// items into always-hidden on the notched display. A pure display switch must
/// not advance the gate.
@Suite("Window ID change gate")
struct WindowIDsChangedGateTests {
    private let d1: CGDirectDisplayID = 1
    private let d2: CGDirectDisplayID = 2

    /// Same display, a previously-seen window is gone: a real change (item quit
    /// / relaunch). Must fire.
    @Test("A missing window on the same display fires the gate")
    func sameDisplayMissingWindowFires() {
        #expect(
            MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12],
                current: [10, 11], // 12 disappeared
                previousDisplayID: d1,
                currentDisplayID: d1
            )
        )
    }

    /// Same display, every previous window still present (pure additions are
    /// owned by another path): must not fire.
    @Test("Pure additions on the same display do not fire the gate")
    func sameDisplayNoMissingWindowDoesNotFire() {
        #expect(
            !MenuBarItemManager.windowIDsChanged(
                previous: [10, 11],
                current: [10, 11, 13], // only an addition
                previousDisplayID: d1,
                currentDisplayID: d1
            )
        )
    }

    /// The active menu bar display switched to another screen: the previous
    /// display's windows are gone from the active-space set, but this is not an
    /// item quit. Must NOT fire. This is the fix; it is red against the stub.
    @Test("Switching the active menu bar display does not fire the gate")
    func activeDisplaySwitchDoesNotFire() {
        #expect(
            !MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12], // display 1's windows
                current: [20, 21, 22], // display 2's windows
                previousDisplayID: d1,
                currentDisplayID: d2
            )
        )
    }

    /// First cycle (no previous frame to diff against): must not fire.
    @Test("An empty previous frame does not fire the gate")
    func emptyPreviousDoesNotFire() {
        #expect(
            !MenuBarItemManager.windowIDsChanged(
                previous: [],
                current: [10, 11],
                previousDisplayID: d1,
                currentDisplayID: d1
            )
        )
    }

    /// Control-Center-generic (`Item-N`) windows churn windowIDs while the
    /// bar is otherwise stable (Live Activities, transient CC widgets). The
    /// applySavedLayout call site subtracts the previous frame's CC-generic
    /// windowIDs before diffing so their disappearance can't dispatch a
    /// cursor-hijacking bulk apply (#736). This characterizes that call-site
    /// composition: with the churned window excluded the gate stays quiet,
    /// and a real item disappearing alongside the churn still fires.
    @Test("Control Center generic churn excluded from the diff keeps the gate quiet")
    func ccGenericChurnExcludedFromGate() {
        let previous: Set<CGWindowID> = [10, 11, 42]
        let ccGeneric: Set<CGWindowID> = [42]
        #expect(
            !MenuBarItemManager.windowIDsChanged(
                previous: previous.subtracting(ccGeneric),
                current: [10, 11, 43], // 42 churned into 43
                previousDisplayID: d1,
                currentDisplayID: d1
            )
        )
        #expect(
            MenuBarItemManager.windowIDsChanged(
                previous: previous.subtracting(ccGeneric),
                current: [10, 43], // 11 (a real item) also disappeared
                previousDisplayID: d1,
                currentDisplayID: d1
            )
        )
    }

    /// Unknown display on either side (nil): fall back to the plain
    /// windowID-disappearance signal rather than suppressing a real change.
    @Test("An unknown display falls back to the plain window ID signal")
    func nilDisplayFallsBackToWindowIDSignal() {
        #expect(
            MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12],
                current: [10, 11],
                previousDisplayID: nil,
                currentDisplayID: d1
            )
        )
        #expect(
            MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12],
                current: [10, 11],
                previousDisplayID: d1,
                currentDisplayID: nil
            )
        )
    }
}
