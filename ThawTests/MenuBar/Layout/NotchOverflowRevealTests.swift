//
//  NotchOverflowRevealTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Whether notch overflow forces the Thaw Bar as the reveal mechanism.
///
/// Inline expansion cannot show ejected items, since nothing more fits beside the
/// notch, so a display with ejected items reveals through the Thaw Bar unless the user turns that off.
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

    /// Stale ejection state must not force the bar once overflow is off; the items are returning to visible.
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
