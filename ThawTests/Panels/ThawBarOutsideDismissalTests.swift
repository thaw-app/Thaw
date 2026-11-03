//
//  ThawBarOutsideDismissalTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Uses the shared ledger the monitors read. The timestamps are far from any
/// real event's, and the last test leaves a press that dismissed nothing.
@MainActor
@Suite("Thaw Bar outside dismissal", .serialized)
struct ThawBarOutsideDismissalTests {
    @Test("A press that closes a section's bar is noted, so show-on-click doesn't reopen it")
    func sectionDismissalIsNoted() {
        let press = MousePress(type: .leftMouseDown, timestamp: 9_000_000)
        let panel = ThawBarPanel()
        defer { _ = MousePressLedger.shared.admit(MousePress(type: .leftMouseDown, timestamp: 9_000_100)) }

        panel.hide(dismissedBy: press)

        #expect(MousePressLedger.shared.admit(press))
        #expect(MousePressLedger.shared.currentPressDismissedBar)
        #expect(!panel.isVisible)
    }
}

@Suite("Mouse press from an event")
struct MousePressEventTests {
    @Test("A press read from an event keeps its type and timestamp")
    func pressFromEvent() throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 1234.5,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))

        #expect(MousePress(event) == MousePress(type: .rightMouseDown, timestamp: 1234.5))
    }
}
