//
//  NotificationCenterEventsTaskTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct NotificationCenterEventsTaskTests {
    private static let name = Notification.Name("NotificationCenterEventsTaskTests.event")

    /// The app host's main actor is busy, so a result is waited for and not assumed after a fixed sleep.
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test
    func `each posting runs the body once when there is no debounce`() async throws {
        let center = NotificationCenter()
        var runs = 0
        let task = center.eventsTask(named: Self.name) { runs += 1 }
        defer { task.cancel() }
        try await Task.sleep(for: .milliseconds(50))

        center.post(name: Self.name, object: nil)
        center.post(name: Self.name, object: nil)
        try await eventually { runs == 2 }
        try await Task.sleep(for: .milliseconds(100))

        #expect(runs == 2)
    }

    @Test
    func `a burst runs the body once after it goes quiet`() async throws {
        let center = NotificationCenter()
        var runs = 0
        let task = center.eventsTask(named: Self.name, debounce: .milliseconds(100)) { runs += 1 }
        defer { task.cancel() }
        try await Task.sleep(for: .milliseconds(50))

        for _ in 0 ..< 5 {
            center.post(name: Self.name, object: nil)
        }
        #expect(runs == 0)
        try await eventually { runs == 1 }
        try await Task.sleep(for: .milliseconds(300))

        #expect(runs == 1)
    }

    @Test
    func `a cancelled task stops listening`() async throws {
        let center = NotificationCenter()
        var runs = 0
        let task = center.eventsTask(named: Self.name) { runs += 1 }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        try await Task.sleep(for: .milliseconds(50))

        center.post(name: Self.name, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(runs == 0)
    }

    @Test
    func `another name does not run the body`() async throws {
        let center = NotificationCenter()
        var runs = 0
        let task = center.eventsTask(named: Self.name) { runs += 1 }
        defer { task.cancel() }
        try await Task.sleep(for: .milliseconds(50))

        center.post(name: Notification.Name("NotificationCenterEventsTaskTests.other"), object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(runs == 0)
    }
}
