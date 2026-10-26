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

    /// Starts the task with a body that counts its runs and says when each ends, and returns once
    /// the task listens: it adds its observer as it starts on the main actor.
    private func listen(
        on center: NotificationCenter,
        debounce: Duration? = nil
    ) async -> (task: Task<Void, Never>, runs: () -> Int, ran: AsyncStream<Void>) {
        let (ran, signal) = AsyncStream<Void>.makeStream()
        var runs = 0
        let task = center.eventsTask(named: Self.name, debounce: debounce) {
            runs += 1
            signal.yield()
        }
        await mainActorQueueDrained()
        return (task, { runs }, ran)
    }

    @Test
    func `each posting runs the body once when there is no debounce`() async throws {
        let center = NotificationCenter()
        let (task, runs, stream) = await listen(on: center)
        var ran = stream.makeAsyncIterator()
        defer { task.cancel() }

        center.post(name: Self.name, object: nil)
        center.post(name: Self.name, object: nil)
        _ = await ran.next()
        _ = await ran.next()
        try await Task.sleep(for: .milliseconds(100))

        #expect(runs() == 2)
    }

    @Test
    func `a burst runs the body once after it goes quiet`() async throws {
        let center = NotificationCenter()
        let (task, runs, stream) = await listen(on: center, debounce: .milliseconds(100))
        var ran = stream.makeAsyncIterator()
        defer { task.cancel() }

        for _ in 0 ..< 5 {
            center.post(name: Self.name, object: nil)
        }
        #expect(runs() == 0)
        _ = await ran.next()
        try await Task.sleep(for: .milliseconds(300))

        #expect(runs() == 1)
    }

    @Test
    func `a cancelled task stops listening`() async throws {
        let center = NotificationCenter()
        let (task, runs, _) = await listen(on: center)
        task.cancel()
        await task.value

        center.post(name: Self.name, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(runs() == 0)
    }

    @Test
    func `another name does not run the body`() async throws {
        let center = NotificationCenter()
        let (task, runs, _) = await listen(on: center)
        defer { task.cancel() }

        center.post(name: Notification.Name("NotificationCenterEventsTaskTests.other"), object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(runs() == 0)
    }
}
