//
//  MenuBarDragGestureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Command-drag pacing and cleanup")
@MainActor
struct MenuBarDragGestureTests {
    private final class Recorder {
        var time: Duration = .zero
        var events: [(MenuBarDragGesture.Phase, CGPoint, Duration)] = []
        var oversleep: Duration = .zero
        var cancelAtSleep: Int?
        var sleeps = 0

        func sleep(_ duration: Duration) throws {
            sleeps += 1
            time += duration + oversleep
            if sleeps == cancelAtSleep {
                throw CancellationError()
            }
        }

        func post(_ phase: MenuBarDragGesture.Phase, _ point: CGPoint) {
            events.append((phase, point, time))
        }
    }

    @Test("60 Hz sampling keeps the conservative travel and holds")
    func heldTiming() async throws {
        let recorder = Recorder()
        let profile = MenuBarDragGesture.held
        let metrics = try await profile.perform(
            from: .zero,
            to: CGPoint(x: 480, y: 24),
            now: { recorder.time },
            sleep: { try recorder.sleep($0) },
            post: recorder.post
        )
        #expect(metrics.motionEvents >= 48)
        #expect(metrics.motionEvents <= 49)
        #expect(abs(metrics.duration / .milliseconds(1340) - 1) < 1e-9)
        let down = try #require(recorder.events.first { $0.0 == .down })
        let firstDrag = try #require(recorder.events.first { $0.0 == .dragged })
        let lastDrag = try #require(recorder.events.last { $0.0 == .dragged })
        #expect(down.2 == .milliseconds(200))
        #expect(firstDrag.2 - down.2 >= profile.pressHold)
        #expect(lastDrag.1 == CGPoint(x: 480, y: 24))
        #expect(recorder.events.last?.2 == lastDrag.2 + .milliseconds(300))
        #expect(recorder.events.filter { $0.0 == .up }.count == 1)
    }

    @Test("Late wakes bound spatial jumps without catch-up bursts")
    func stalledClock() async throws {
        let recorder = Recorder()
        recorder.oversleep = .milliseconds(70)
        _ = try await MenuBarDragGesture.held.perform(
            from: CGPoint(x: 1000, y: 24),
            to: CGPoint(x: 0, y: 24),
            now: { recorder.time },
            sleep: { try recorder.sleep($0) },
            post: recorder.post
        )
        let drags = recorder.events.filter { $0.0 == .dragged }
        var lastX = 1000.0
        for drag in drags {
            #expect(lastX - drag.1.x <= 50.000001)
            #expect(drag.1.x <= lastX)
            lastX = drag.1.x
        }
        for (previous, next) in zip(drags, drags.dropFirst()) {
            #expect(next.2 - previous.2 >= .milliseconds(70))
        }
        #expect(drags.last?.1 == CGPoint(x: 0, y: 24))
    }

    @Test("Cancellation at every hold/frame releases only after a press", arguments: [1, 2, 3, 12, 51])
    func cancellation(sleepIndex: Int) async {
        let recorder = Recorder()
        recorder.cancelAtSleep = sleepIndex
        await #expect(throws: CancellationError.self) {
            _ = try await MenuBarDragGesture.held.perform(
                from: .zero,
                to: CGPoint(x: 480, y: 0),
                now: { recorder.time },
                sleep: { try recorder.sleep($0) },
                post: recorder.post
            )
        }
        let pressed = recorder.events.contains { $0.0 == .down }
        let releases = recorder.events.filter { $0.0 == .up }
        #expect(releases.count == (pressed ? 1 : 0))
        if pressed {
            let lastAccepted = recorder.events.last { $0.0 == .dragged || $0.0 == .down }
            #expect(releases.last?.1 == lastAccepted?.1)
        }
    }

    @Test("A cancelled task cannot post even if the injected sleep ignores cancellation")
    func alreadyCancelled() async {
        let recorder = Recorder()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) {
                _ = try await MenuBarDragGesture.held.perform(
                    from: .zero,
                    to: CGPoint(x: 100, y: 0),
                    now: { recorder.time },
                    sleep: { recorder.time += $0 },
                    post: recorder.post
                )
            }
        }
        await task.value
        #expect(recorder.events.isEmpty)
    }

    @Test("Posting failure releases at the last accepted point")
    func rejectedFrame() async {
        enum Rejected: Error { case frame }
        let recorder = Recorder()
        await #expect(throws: Rejected.self) {
            _ = try await MenuBarDragGesture.held.perform(
                from: .zero,
                to: CGPoint(x: 480, y: 0),
                now: { recorder.time },
                sleep: { try recorder.sleep($0) },
                post: { phase, point in
                    if phase == .dragged, point.x > 25 {
                        throw Rejected.frame
                    }
                    recorder.post(phase, point)
                }
            )
        }
        #expect(recorder.events.last?.0 == .up)
        #expect(recorder.events.last?.1 == recorder.events.last { $0.0 == .dragged }?.1)
    }
}
