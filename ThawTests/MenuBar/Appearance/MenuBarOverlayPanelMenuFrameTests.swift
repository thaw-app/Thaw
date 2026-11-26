//
//  MenuBarOverlayPanelMenuFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Menu bar overlay application menu frame")
struct MenuBarOverlayPanelMenuFrameTests {
    private static let narrow = CGRect(x: 0, y: 0, width: 200, height: 24)
    private static let wide = CGRect(x: 0, y: 0, width: 320, height: 24)

    /// Runs the settle loop over frames, one per read, nil once they run out.
    @MainActor
    private final class Run {
        private var frames: [CGRect?]
        private(set) var reads = 0
        private(set) var waits = 0
        private(set) var published: [CGRect] = []

        init(_ frames: [CGRect?], deadline: ContinuousClock.Instant = .now + .seconds(10), failWaits: Bool = false) async {
            self.frames = frames
            await MenuBarOverlayPanel.settleApplicationMenuFrame(
                deadline: deadline,
                read: {
                    self.reads += 1
                    return self.frames.isEmpty ? nil : self.frames.removeFirst()
                },
                publish: { self.published.append($0) },
                wait: {
                    self.waits += 1
                    if failWaits { throw CancellationError() }
                }
            )
        }
    }

    @Test("A failed read is followed by a wait, so ten failures take ten waits")
    func failedReadsWait() async {
        let run = await Run([])
        #expect(run.reads == 10)
        #expect(run.waits == 10)
        #expect(run.published.isEmpty)
    }

    @Test("A frame read three more times in a row ends the loop after one publish")
    func steadyFrameSettles() async {
        let run = await Run(Array(repeating: Self.narrow, count: 10))
        #expect(run.published == [Self.narrow])
        #expect(run.reads == 4)
    }

    @Test("A frame that changes is published again and restarts the count")
    func changedFrameRepublishes() async {
        let run = await Run([Self.narrow, nil, Self.wide, Self.wide, Self.wide, Self.wide])
        #expect(run.published == [Self.narrow, Self.wide])
        #expect(run.reads == 6)
    }

    @Test("A cancelled wait ends the loop")
    func cancelledWaitStops() async {
        let run = await Run([], failWaits: true)
        #expect(run.reads == 1)
    }

    @Test("A task cancelled before its first read reads nothing")
    func cancelledTaskReadsNothing() async {
        let task = Task { await Run([Self.narrow]) }
        task.cancel()
        let run = await task.value
        #expect(run.reads == 0)
        #expect(run.published.isEmpty)
    }

    @Test("Nothing is read once the deadline has passed")
    func pastDeadlineReadsNothing() async {
        let run = await Run([Self.narrow], deadline: .now - .seconds(1))
        #expect(run.reads == 0)
        #expect(run.published.isEmpty)
    }
}
