//
//  MoveLayoutSettlingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The polling loop behind `waitForLayoutToSettle`: a landing is judged
/// only once two consecutive readings of the bar agree, and never later
/// than the poll budget.
@Suite("Move layout settling")
struct MoveLayoutSettlingTests {
    @Test("Two matching consecutive readings settle the value")
    func settlesOnTheFirstRepeat() async {
        let values = [1465, 1445, 1427, 1427, 1400]
        var index = 0
        var waits = 0

        let outcome = await MenuBarItemManager.settledReading(
            maxPolls: 10,
            read: {
                defer { index += 1 }
                return values[index]
            },
            wait: { waits += 1 }
        )

        #expect(outcome.settled)
        #expect(outcome.value == 1427)
        #expect(index == 4)
        #expect(waits == 3)
    }

    @Test("A bar that keeps moving gives up after the poll budget")
    func givesUpAfterTheBudget() async {
        var next = 0

        let outcome = await MenuBarItemManager.settledReading(
            maxPolls: 4,
            read: {
                next += 1
                return next
            },
            wait: {}
        )

        #expect(!outcome.settled)
        #expect(outcome.value == 4)
    }

    @Test("A single-poll budget returns the first reading unconfirmed")
    func singlePollIsUnconfirmed() async {
        var waits = 0

        let outcome = await MenuBarItemManager.settledReading(
            maxPolls: 1,
            read: { "only" },
            wait: { waits += 1 }
        )

        #expect(!outcome.settled)
        #expect(outcome.value == "only")
        #expect(waits == 0)
    }
}
