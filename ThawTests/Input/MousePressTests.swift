//
//  MousePressTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

private func press(_ type: NSEvent.EventType = .leftMouseDown, at timestamp: TimeInterval) -> MousePress {
    MousePress(type: type, timestamp: timestamp)
}

/// Telling one physical press seen twice from two presses.
@Suite("Mouse press identity")
struct MousePressTests {
    @Test("The same event seen twice is one press")
    func sameTimestamp() {
        #expect(press(at: 100).isSamePress(as: press(at: 100)))
    }

    @Test("A sighting that drifted a few milliseconds is still one press")
    func smallDrift() {
        #expect(press(at: 100.005).isSamePress(as: press(at: 100)))
        #expect(press(at: 100).isSamePress(as: press(at: 100.005)))
    }

    @Test("A deliberate double-click stays two presses, even a very fast one")
    func deliberateDoubleClick() {
        #expect(!press(at: 100.06).isSamePress(as: press(at: 100)))
        #expect(!press(at: 100.5).isSamePress(as: press(at: 100)))
    }

    @Test("Sameness ends at the tolerance")
    func toleranceBoundary() {
        #expect(!press(at: 100 + MousePress.sameness * 1.5).isSamePress(as: press(at: 100)))
        #expect(press(at: 100 + MousePress.sameness / 2).isSamePress(as: press(at: 100)))
    }

    @Test("With nothing to compare, a press is new")
    func noEarlierPress() {
        #expect(!press(at: 100).isSamePress(as: nil))
    }

    @Test("A left and a right press at the same moment are different presses")
    func differentButtons() {
        #expect(!press(.rightMouseDown, at: 100).isSamePress(as: press(.leftMouseDown, at: 100)))
    }
}

/// The two monitors that see each press, in the order the issue 1440 log shows.
@Suite("Mouse press ledger")
@MainActor
struct MousePressLedgerTests {
    @Test("A repeat sighting is refused, however late it is handled")
    func repeatIsRefused() {
        let ledger = MousePressLedger()
        #expect(ledger.admit(press(at: 100)))
        #expect(!ledger.admit(press(at: 100)))
    }

    @Test("Both clicks of a double-click are admitted")
    func doubleClickIsAdmitted() {
        let ledger = MousePressLedger()
        #expect(ledger.admit(press(at: 100)))
        #expect(ledger.admit(press(at: 100.25)))
    }

    @Test("A press that closed the bar counts as having done so when show-on-click handles it")
    func dismissingPressDoesNotReopen() {
        let ledger = MousePressLedger()
        ledger.noteDismissal(by: press(at: 200))
        #expect(ledger.admit(press(at: 200)))
        #expect(ledger.currentPressDismissedBar)
    }

    @Test("The next press after a dismissal may open the bar again")
    func nextPressMayReopen() {
        let ledger = MousePressLedger()
        ledger.noteDismissal(by: press(at: 200))
        _ = ledger.admit(press(at: 200))
        #expect(ledger.admit(press(at: 200.6)))
        #expect(!ledger.currentPressDismissedBar)
    }

    @Test("A press with no dismissal behind it may open the bar")
    func noDismissal() {
        let ledger = MousePressLedger()
        #expect(!ledger.currentPressDismissedBar)
        _ = ledger.admit(press(at: 300))
        #expect(!ledger.currentPressDismissedBar)
    }

    @Test("A right-click that closed the bar says nothing about a left click")
    func rightClickDismissal() {
        let ledger = MousePressLedger()
        ledger.noteDismissal(by: press(.rightMouseDown, at: 400))
        _ = ledger.admit(press(.leftMouseDown, at: 400))
        #expect(!ledger.currentPressDismissedBar)
    }
}
