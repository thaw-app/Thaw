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
    /// Overflow turned off must win over stale ejection bookkeeping: the items are on their way back.
    @Test("Only ejected items with overflow and the preference on force the Thaw Bar", arguments: [
        (true, true, true, true),
        (true, true, false, false),
        (true, false, true, false),
        (false, true, true, false),
    ])
    func forcesThawBar(overflowEnabled: Bool, useThawBarOnOverflow: Bool, hasEjectedItems: Bool, forces: Bool) {
        #expect(MenuBarSection.forcesThawBarForNotchOverflow(
            overflowEnabled: overflowEnabled,
            useThawBarOnOverflow: useThawBarOnOverflow,
            hasEjectedItems: hasEjectedItems
        ) == forces)
    }
}
