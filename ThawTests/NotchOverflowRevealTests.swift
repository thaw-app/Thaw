//
//  NotchOverflowRevealTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Tests for the rule that decides whether notch overflow forces the Thaw Bar
/// as the reveal mechanism for hidden items.
///
/// Expanding the hidden section inline cannot show items that overflow ejected
/// — they were ejected precisely because nothing more fits beside the notch —
/// so a display with ejected items reveals through the Thaw Bar instead, unless
/// the user turns that off.
@Suite("Notch overflow reveal")
struct NotchOverflowRevealTests {
    @Test("Ejected items with the preference on force the Thaw Bar")
    func forcesBarWhenOverflowEnabledPreferenceOnAndItemsEjected() {
        #expect(
            MenuBarSection.forcesIceBarForNotchOverflow(
                overflowEnabled: true,
                useThawBarOnOverflow: true,
                hasEjectedItems: true
            )
        )
    }

    @Test("Nothing ejected does not force the Thaw Bar")
    func doesNotForceBarWhenNothingIsEjected() {
        #expect(
            !MenuBarSection.forcesIceBarForNotchOverflow(
                overflowEnabled: true,
                useThawBarOnOverflow: true,
                hasEjectedItems: false
            )
        )
    }

    @Test("The preference turned off does not force the Thaw Bar")
    func doesNotForceBarWhenPreferenceIsOff() {
        #expect(
            !MenuBarSection.forcesIceBarForNotchOverflow(
                overflowEnabled: true,
                useThawBarOnOverflow: false,
                hasEjectedItems: true
            )
        )
    }

    /// Stale ejection bookkeeping must not keep forcing the bar after the user
    /// turns overflow off; the items are on their way back to visible.
    @Test("Overflow disabled does not force the Thaw Bar")
    func doesNotForceBarWhenOverflowIsDisabled() {
        #expect(
            !MenuBarSection.forcesIceBarForNotchOverflow(
                overflowEnabled: false,
                useThawBarOnOverflow: true,
                hasEjectedItems: true
            )
        )
    }
}
