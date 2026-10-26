//
//  DisplayEnvironmentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

@MainActor
@Suite("Display environment", .timeLimit(.minutes(1)))
struct DisplayEnvironmentTests {
    private static let single = DisplayArrangement(frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982)], mainDisplayID: 1)
    private static let docked = DisplayArrangement(
        frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982), 2: CGRect(x: 1512, y: 0, width: 2560, height: 1440)],
        mainDisplayID: 1
    )

    @Test("A burst of five postings invalidates at once and publishes one snapshot")
    func burstPublishesOnce() async {
        let harness = EnvironmentHarness(baseline: Self.single, reads: [Self.docked])
        harness.environment.start()
        defer { harness.environment.stop() }

        for _ in 0 ..< 5 {
            harness.center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        #expect(!harness.environment.snapshot.isSettled, "Readers must see the change before the settle")

        await harness.environment.waitUntilSettled()
        #expect(harness.environment.snapshot.isSettled)
        #expect(harness.environment.snapshot.generation == 1)
        #expect(harness.environment.snapshot.change == .displayAdded)
        #expect(harness.readCount == 2)
        #expect(harness.sleeps == [.milliseconds(300), .milliseconds(150)])
    }

    @Test("Geometry that never repeats ends the settle after six reads, on the last one")
    func readCapEndsSettle() async {
        let moving = (0 ..< 8).map { index in
            DisplayArrangement(frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982), 2: CGRect(x: 1512 + index, y: 0, width: 2560, height: 1440)], mainDisplayID: 1)
        }
        let harness = EnvironmentHarness(baseline: Self.single, reads: moving)

        harness.environment.noteScreenParametersChanged()
        await harness.environment.waitUntilSettled()

        #expect(harness.readCount == 6)
        #expect(harness.environment.snapshot.arrangement == moving[5])
        #expect(harness.environment.snapshot.generation == 1)
        #expect(harness.sleeps == [.milliseconds(300)] + Array(repeating: .milliseconds(150), count: 5))
    }

    @Test("Each settled change raises the generation once, and an unchanged settle does not")
    func generationPerSettledChange() async {
        let harness = EnvironmentHarness(baseline: Self.single, reads: [Self.docked, Self.docked, Self.docked, Self.docked, Self.single])

        harness.environment.noteScreenParametersChanged()
        await harness.environment.waitUntilSettled()
        #expect(harness.environment.snapshot.generation == 1)

        harness.environment.noteScreenParametersChanged()
        await harness.environment.waitUntilSettled()
        #expect(harness.environment.snapshot.generation == 1)
        #expect(harness.environment.snapshot.isSettled)

        harness.environment.noteScreenParametersChanged()
        await harness.environment.waitUntilSettled()
        #expect(harness.environment.snapshot.generation == 2)
        #expect(harness.environment.snapshot.change == .displayRemoved)
    }

    @Test("Readers hear every posting at once and one settle per burst, unchanged settles included")
    func publishersReportPostingsAndSettles() async {
        let harness = EnvironmentHarness(baseline: Self.single, reads: [Self.docked, Self.docked, Self.docked, Self.docked])
        var invalidations = 0
        var settles = [EnvironmentChange]()
        let invalidated = harness.environment.invalidations.sink { invalidations += 1 }
        let settled = harness.environment.settlements.sink { settles.append($0) }
        defer {
            invalidated.cancel()
            settled.cancel()
        }

        for _ in 0 ..< 3 {
            harness.environment.noteScreenParametersChanged()
        }
        #expect(invalidations == 3)
        #expect(settles.isEmpty)
        await harness.environment.waitUntilSettled()
        #expect(settles == [.displayAdded])

        harness.environment.noteScreenParametersChanged()
        await harness.environment.waitUntilSettled()
        #expect(invalidations == 4)
        #expect(settles == [.displayAdded, .none])
    }
}

/// Scripted geometry reads and recorded sleeps, so the settle runs without real time.
@MainActor
private final class EnvironmentHarness {
    let center = NotificationCenter()
    let environment: DisplayEnvironment
    private let recorder: EnvironmentRecorder

    var readCount: Int {
        recorder.readCount
    }

    var sleeps: [Duration] {
        recorder.sleeps
    }

    init(baseline: DisplayArrangement, reads: [DisplayArrangement]) {
        let recorder = EnvironmentRecorder(reads: reads)
        self.recorder = recorder
        environment = DisplayEnvironment(
            center: center,
            timing: EnvironmentSettle.Timing(),
            baseline: baseline,
            read: { [recorder] in recorder.read() },
            sleep: { [recorder] in try await recorder.sleep(for: $0) }
        )
    }
}

@MainActor
private final class EnvironmentRecorder {
    private(set) var readCount = 0
    private(set) var sleeps: [Duration] = []
    private let reads: [DisplayArrangement]

    init(reads: [DisplayArrangement]) {
        self.reads = reads
    }

    func read() -> DisplayArrangement {
        defer { readCount += 1 }
        return reads[min(readCount, reads.count - 1)]
    }

    /// Records the wait and yields once, throwing when the settle was replaced, as Task.sleep would.
    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        await Task.yield()
        try Task.checkCancellation()
    }
}
