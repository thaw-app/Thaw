//
//  MenuBarSectionLayout+Overflow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// Pure presentation decisions for sections, kept apart from MenuBarSection.swift,
// which needs a live ControlItem, AppState and NSScreen. New decision logic
// belongs here. Covered by NotchOverflowRevealTests.

extension MenuBarSection {
    /// Whether notch overflow forces the Thaw Bar on a display whose Thaw Bar
    /// setting is off, since ejected items cannot fit inline beside the notch.
    ///
    /// The preference parameter has no setting yet, so the caller passes true.
    /// The overflow-enabled gate stops stale ejection state forcing the bar
    /// after the user turns overflow off.
    static nonisolated func forcesThawBarForNotchOverflow(
        overflowEnabled: Bool,
        useThawBarOnOverflow: Bool,
        hasEjectedItems: Bool
    ) -> Bool {
        overflowEnabled && useThawBarOnOverflow && hasEjectedItems
    }
}
