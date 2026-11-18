//
//  OpenedItemRecaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins how the picture of an item opened from the Thaw Bar waits for its menu to close.
@MainActor
@Suite("Opened item recapture")
struct OpenedItemRecaptureTests {
    /// Scripted time, menu answers and tries for one retake. The last answer of each
    /// list repeats once the others are used up.
    @MainActor
    final class Script {
        private(set) var now = ContinuousClock.now
        private var menuAnswers: [Bool]
        private var attemptResults: [OpenedItemRecapture.Attempt]
        private(set) var menuChecks = 0
        private(set) var attempts = 0

        init(menuOpen: [Bool], attempts: [OpenedItemRecapture.Attempt]) {
            menuAnswers = menuOpen
            attemptResults = attempts
        }

        var steps: OpenedItemRecapture.Steps {
            OpenedItemRecapture.Steps(
                isMenuOpen: { [self] in
                    menuChecks += 1
                    return menuAnswers.count > 1 ? menuAnswers.removeFirst() : menuAnswers.first ?? false
                },
                attempt: { [self] in
                    attempts += 1
                    return attemptResults.count > 1 ? attemptResults.removeFirst() : attemptResults.first ?? .missed
                },
                sleep: { [self] in now = now.advanced(by: $0) },
                now: { [self] in now }
            )
        }
    }

    @Test("The picture waits while the item's menu is open, then is taken once")
    func waitsForTheMenuToClose() async {
        let script = Script(menuOpen: [true, true, false], attempts: [.stored])

        let outcome = await OpenedItemRecapture.run(script.steps)

        #expect(outcome == .stored)
        #expect(script.menuChecks == 3)
        #expect(script.attempts == 1)
    }

    @Test("An item with no menu is photographed after the first check")
    func noMenuIsPhotographedAtOnce() async {
        let script = Script(menuOpen: [false], attempts: [.stored])

        #expect(await OpenedItemRecapture.run(script.steps) == .stored)
        #expect(script.menuChecks == 1)
    }

    @Test("A menu that opened during the try makes it try again")
    func menuDuringTheTryRetries() async {
        let script = Script(menuOpen: [false], attempts: [.menuOpened, .stored])

        #expect(await OpenedItemRecapture.run(script.steps) == .stored)
        #expect(script.attempts == 2)
    }

    @Test("An item hidden again before its picture keeps its old picture, without another try")
    func missedPictureEnds() async {
        let script = Script(menuOpen: [false], attempts: [.missed])

        #expect(await OpenedItemRecapture.run(script.steps) == .missed)
        #expect(script.attempts == 1)
    }

    @Test("A menu left open past the limit gives up on the picture")
    func menuOpenPastTheLimitGivesUp() async {
        let script = Script(menuOpen: [true], attempts: [.stored])
        let start = script.now

        #expect(await OpenedItemRecapture.run(script.steps) == .missed)
        #expect(script.attempts == 0)
        #expect(start.duration(to: script.now) >= OpenedItemRecapture.menuWaitLimit)
    }

    @Test("A retake replaced by a newer one ends as cancelled")
    func cancelledRetakeEnds() async {
        let script = Script(menuOpen: [true], attempts: [.missed])

        let retake = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await OpenedItemRecapture.run(script.steps)
        }

        #expect(await retake.value == .cancelled)
        #expect(script.attempts == 0)
    }
}
