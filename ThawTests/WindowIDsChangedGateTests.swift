//
//  WindowIDsChangedGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

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
final class WindowIDsChangedGateTests: XCTestCase {
    private let d1: CGDirectDisplayID = 1
    private let d2: CGDirectDisplayID = 2

    /// Same display, a previously-seen window is gone: a real change (item quit
    /// / relaunch). Must fire.
    func testSameDisplayMissingWindowFires() {
        XCTAssertTrue(
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
    func testSameDisplayNoMissingWindowDoesNotFire() {
        XCTAssertFalse(
            MenuBarItemManager.windowIDsChanged(
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
    func testActiveDisplaySwitchDoesNotFire() {
        XCTAssertFalse(
            MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12], // display 1's windows
                current: [20, 21, 22], // display 2's windows
                previousDisplayID: d1,
                currentDisplayID: d2
            )
        )
    }

    /// First cycle (no previous frame to diff against): must not fire.
    func testEmptyPreviousDoesNotFire() {
        XCTAssertFalse(
            MenuBarItemManager.windowIDsChanged(
                previous: [],
                current: [10, 11],
                previousDisplayID: d1,
                currentDisplayID: d1
            )
        )
    }

    /// Unknown display on either side (nil): fall back to the plain
    /// windowID-disappearance signal rather than suppressing a real change.
    func testNilDisplayFallsBackToWindowIDSignal() {
        XCTAssertTrue(
            MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12],
                current: [10, 11],
                previousDisplayID: nil,
                currentDisplayID: d1
            )
        )
        XCTAssertTrue(
            MenuBarItemManager.windowIDsChanged(
                previous: [10, 11, 12],
                current: [10, 11],
                previousDisplayID: d1,
                currentDisplayID: nil
            )
        )
    }
}
