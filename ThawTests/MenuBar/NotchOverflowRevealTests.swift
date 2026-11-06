//
//  NotchOverflowRevealTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Inline reveals cannot fit overflow-ejected items beside the notch; use the Thaw Bar unless the user opts out.
@Suite("Notch overflow reveal")
struct NotchOverflowRevealTests {
    @Test("Ejected items with the preference on force the Thaw Bar")
    func forcesBarWhenOverflowEnabledPreferenceOnAndItemsEjected() {
        #expect(
            MenuBarSection.forcesThawBarForNotchOverflow(
                overflowEnabled: true,
                useThawBarOnOverflow: true,
                hasEjectedItems: true
            )
        )
    }

    @Test("Nothing ejected does not force the Thaw Bar")
    func doesNotForceBarWhenNothingIsEjected() {
        #expect(
            !MenuBarSection.forcesThawBarForNotchOverflow(
                overflowEnabled: true,
                useThawBarOnOverflow: true,
                hasEjectedItems: false
            )
        )
    }

    @Test("The preference turned off does not force the Thaw Bar")
    func doesNotForceBarWhenPreferenceIsOff() {
        #expect(
            !MenuBarSection.forcesThawBarForNotchOverflow(
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
            !MenuBarSection.forcesThawBarForNotchOverflow(
                overflowEnabled: false,
                useThawBarOnOverflow: true,
                hasEjectedItems: true
            )
        )
    }
}
