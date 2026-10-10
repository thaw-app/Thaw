//
//  SyntheticDragInputSessionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Synthetic drag input ownership")
@MainActor
struct SyntheticDragInputSessionTests {
    @MainActor
    private final class Recorder {
        var acquired = 0
        var restored = 0
        var reasserted = 0
        var events: [(MenuBarDragGesture.Phase, CGPoint)] = []

        var environment: SyntheticDragInputSession.Environment {
            .init(
                acquire: {
                    self.acquired += 1
                    return { self.restored += 1 }
                },
                post: { self.events.append(($0, $1)) },
                reassert: { self.reasserted += 1 }
            )
        }
    }

    @Test("Successful release and repeated cleanup restore input once")
    func normalCompletion() throws {
        let recorder = Recorder()
        let session = try SyntheticDragInputSession(environment: recorder.environment)
        try session.post(.down, at: .zero)
        try session.post(.dragged, at: CGPoint(x: 10, y: 0))
        try session.post(.up, at: CGPoint(x: 10, y: 0))
        session.finish()
        session.finish()
        #expect(recorder.acquired == 1)
        #expect(recorder.restored == 1)
        #expect(recorder.events.filter { $0.0 == .up }.count == 1)
    }

    @Test("Watchdog cleanup releases at the last point and rejects later frames")
    func expiredSession() throws {
        let recorder = Recorder()
        let session = try SyntheticDragInputSession(environment: recorder.environment)
        try session.post(.down, at: .zero)
        try session.post(.dragged, at: CGPoint(x: 20, y: 0))
        // The watchdog uses this same synchronous exit; no wall-clock wait.
        session.finish()
        #expect(throws: (any Error).self) {
            try session.post(.dragged, at: CGPoint(x: 100, y: 0))
        }
        session.finish()
        #expect(recorder.events.map(\.0) == [.down, .dragged, .up])
        #expect(recorder.events.last?.1 == CGPoint(x: 20, y: 0))
        #expect(recorder.reasserted == 2)
        #expect(recorder.restored == 1)
    }

    @Test("Cancelling the gesture releases the button before restoring input")
    func cancelledGesture() async throws {
        let recorder = Recorder()
        let session = try SyntheticDragInputSession(environment: recorder.environment)
        defer { session.finish() }
        var time: Duration = .zero
        var sleeps = 0
        await #expect(throws: CancellationError.self) {
            _ = try await MenuBarDragGesture.held.perform(
                from: .zero,
                to: CGPoint(x: 480, y: 0),
                now: { time },
                sleep: {
                    sleeps += 1
                    if sleeps == 4 {
                        throw CancellationError()
                    }
                    time += $0
                },
                post: { try session.post($0, at: $1) }
            )
        }
        #expect(recorder.events.last?.0 == .up)
        session.finish()
        #expect(recorder.restored == 1)
        #expect(recorder.events.filter { $0.0 == .up }.count == 1)
    }

    @Test("Failed acquisition never posts an event")
    func acquisitionFailure() {
        enum Refused: Error { case input }
        let recorder = Recorder()
        var environment = recorder.environment
        environment.acquire = { throw Refused.input }
        #expect(throws: Refused.self) {
            _ = try SyntheticDragInputSession(
                environment: environment
            )
        }
        #expect(recorder.events.isEmpty)
        #expect(recorder.restored == 0)
    }
}
