//
//  WindowIDsChangedGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The windowID-change gate that decides whether a cycle re-applies the saved layout.
///
/// It fires when a known window disappears. With "Displays have separate
/// Spaces", the bar following focus to another display drops the previous
/// display's windows from the active-space list, which fired a full re-sort on
/// every focus change and drifted items into always-hidden. A display switch
/// must not advance the gate.
@Suite("Window ID change gate")
struct WindowIDsChangedGateTests {
    private let d1: CGDirectDisplayID = 1
    private let d2: CGDirectDisplayID = 2

    /// A known window gone on the same display is a real quit or relaunch.
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

    /// Pure additions are owned by another path.
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

    /// The previous display's windows leave the active-space set, but nothing quit.
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

    /// First cycle, nothing to diff against.
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

    /// Control Center generic (`Item-N`) windows churn IDs while the bar is stable
    /// (Live Activities, transient widgets). applySavedLayout subtracts them before
    /// diffing so churn cannot trigger a bulk apply (#736); a real disappearance still fires.
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

    /// With a nil display on either side, fall back to plain disappearance rather than suppress a real change.
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
