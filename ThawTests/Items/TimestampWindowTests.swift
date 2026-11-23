//
//  TimestampWindowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Timestamp window")
struct TimestampWindowTests {
    private let start = ContinuousClock.now
    private let length = Duration.seconds(10)

    private func window(expiry: TimestampWindow.Expiry) -> TimestampWindow {
        var window = TimestampWindow(length: length, expiry: expiry)
        window.record(at: start)
        window.record(at: start + .seconds(5))
        return window
    }

    @Test("An event as old as the window drops out at its length, or only once past it", arguments: [
        (TimestampWindow.Expiry.atLength, 1),
        (.pastLength, 2),
    ])
    func edgeOfTheWindow(expiry: TimestampWindow.Expiry, countAtLength: Int) {
        var events = window(expiry: expiry)
        events.removeExpired(at: start + length)
        #expect(events.count == countAtLength)
        events.removeExpired(at: start + length + .nanoseconds(1))
        #expect(events.count == 1)
    }

    @Test("Recording drops what has expired first, and removeAll empties the window")
    func recordAndRemoveAll() {
        var events = window(expiry: .atLength)
        events.record(at: start + .seconds(12))
        #expect(events.count == 2)
        events.removeAll()
        #expect(events.count == 0)
    }
}
