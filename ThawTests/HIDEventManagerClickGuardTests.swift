//
//  HIDEventManagerClickGuardTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterizes the two pure decision points extracted from
/// `HIDEventManager`'s show-on-click guard:
///
/// - `nextGuardState(from:given:)` — the `GuardMouseUpState`
///   swallow-then-disarm transition table.
/// - `shouldSwallowClick(clickLocation:guardRegion:isDoubleClick:withinDoubleClickWindow:)`
///   — the guard-region / double-click-window predicate that decides
///   whether a click is swallowed by the guard tap.
///
/// These do not drive the live `CGEventTap`; they test the extracted pure
/// statics the instance methods call into.
final class HIDEventManagerClickGuardTests: XCTestCase {
    // MARK: - nextGuardState

    /// A reveal click (double-click-in-region reveal of the always-hidden
    /// section, or an option-click toggle) arms the guard to swallow the
    /// next mouse-up and defer disarming until it arrives.
    func testNextGuardState_ArmOnRevealClick() {
        XCTAssertEqual(
            HIDEventManager.nextGuardState(from: .idle, given: .swallowThenDisarm),
            .swallowingThenDisarm
        )
    }

    /// After swallowing one mouse-up, the guard returns to idle so the next
    /// legitimate click is not also swallowed.
    func testNextGuardState_DisarmAfterSwallow() {
        XCTAssertEqual(
            HIDEventManager.nextGuardState(from: .swallowing, given: .mouseUp),
            .idle
        )
    }

    /// The section-toggle-survival invariant: if a disarm is requested (e.g.
    /// `stopAll()` during a manager rebuild) while the guard is mid-swallow,
    /// the guard must not drop straight to `.idle` — a stray mouse-up could
    /// then leak past the (now-stopped) tap to the underlying app. Instead
    /// it defers to `.swallowingThenDisarm` so the pending mouse-up is still
    /// accounted for.
    func testNextGuardState_ToggleSurvivesRebuild() {
        XCTAssertEqual(
            HIDEventManager.nextGuardState(from: .swallowing, given: .disarmRequested),
            .swallowingThenDisarm
        )
    }

    /// A disarm request while already idle is a no-op — there is no pending
    /// mouse-up to account for, so the guard stays idle.
    func testNextGuardState_DisarmRequestWhileIdleStaysIdle() {
        XCTAssertEqual(
            HIDEventManager.nextGuardState(from: .idle, given: .disarmRequested),
            .idle
        )
    }

    // MARK: - shouldSwallowClick

    /// A click landing inside the guard region, within the double-click
    /// window, is swallowed.
    func testShouldSwallowClick_InsideGuardRegion() {
        let region = CGRect(x: 100, y: 0, width: 44, height: 28)
        let clickLocation = CGPoint(x: region.midX, y: region.midY)

        XCTAssertTrue(
            HIDEventManager.shouldSwallowClick(
                clickLocation: clickLocation,
                guardRegion: region,
                isDoubleClick: false,
                withinDoubleClickWindow: true
            )
        )
    }

    /// A click outside the guard region is never swallowed, even while the
    /// double-click window is still open.
    func testShouldSwallowClick_OutsideGuardRegion() {
        let region = CGRect(x: 100, y: 0, width: 44, height: 28)
        let clickLocation = CGPoint(x: region.maxX + 50, y: region.midY)

        XCTAssertFalse(
            HIDEventManager.shouldSwallowClick(
                clickLocation: clickLocation,
                guardRegion: region,
                isDoubleClick: false,
                withinDoubleClickWindow: true
            )
        )
    }

    /// A second click, recognized as part of a double click, landing inside
    /// the guard region while its window is still open is swallowed — the
    /// region-swallow logic does not stop applying just because the click
    /// completes a double click.
    func testShouldSwallowClick_DoubleClickWindow() {
        let region = CGRect(x: 100, y: 0, width: 44, height: 28)
        let clickLocation = CGPoint(x: region.midX, y: region.midY)

        XCTAssertTrue(
            HIDEventManager.shouldSwallowClick(
                clickLocation: clickLocation,
                guardRegion: region,
                isDoubleClick: true,
                withinDoubleClickWindow: true
            )
        )

        // Once the double-click window has closed, the same click location
        // is no longer swallowed.
        XCTAssertFalse(
            HIDEventManager.shouldSwallowClick(
                clickLocation: clickLocation,
                guardRegion: region,
                isDoubleClick: true,
                withinDoubleClickWindow: false
            )
        )
    }
}
