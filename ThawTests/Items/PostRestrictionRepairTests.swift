//
//  PostRestrictionRepairTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Observation
import Testing
@testable import Thaw
import ThawCapture

/// A repair pass that answers from a script and can be held open, so a test can act while it runs.
@MainActor
@Observable
final class ScriptedRepairPass {
    var answers: [Bool?]
    private(set) var runs = 0
    private(set) var isWaiting = false
    @ObservationIgnored var holdsNextRun = false
    @ObservationIgnored private var gate: CheckedContinuation<Void, Never>?

    init(answers: [Bool?]) {
        self.answers = answers
    }

    func run() async -> Bool? {
        runs += 1
        if holdsNextRun {
            holdsNextRun = false
            isWaiting = true
            await withCheckedContinuation { gate = $0 }
            isWaiting = false
        }
        return answers.isEmpty ? false : answers.removeFirst()
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
@Suite("Post-restriction repair schedule")
struct PostRestrictionRepairScheduleTests {
    private let sleeps = RecordedSleeps()

    private func makeSchedule() -> PostRestrictionRepairSchedule {
        let sleeps = sleeps
        return PostRestrictionRepairSchedule(sleep: { try sleeps.sleep(for: $0) })
    }

    @Test("One pass runs after the reflow delay when nothing stays parked")
    func singlePass() async {
        let schedule = makeSchedule()
        let pass = ScriptedRepairPass(answers: [false])

        schedule.schedule { await pass.run() }
        await schedule.task?.value

        #expect(pass.runs == 1)
        #expect(sleeps.durations == [PostRestrictionRepairSchedule.firstDelay])
        #expect(!schedule.isRunning)
    }

    @Test("Parked items keep the pass polling, at most four more times")
    func pollsWhileParked() async {
        let schedule = makeSchedule()
        let pass = ScriptedRepairPass(answers: Array(repeating: true, count: 10))

        schedule.schedule { await pass.run() }
        await schedule.task?.value

        #expect(pass.runs == 1 + PostRestrictionRepairSchedule.maximumPolls)
        #expect(sleeps.durations.dropFirst().allSatisfy { $0 == PostRestrictionRepairSchedule.pollInterval })
    }

    @Test("A superseded pass stops the polling")
    func supersededPassStops() async {
        let schedule = makeSchedule()
        let pass = ScriptedRepairPass(answers: [true, nil, true])

        schedule.schedule { await pass.run() }
        await schedule.task?.value

        #expect(pass.runs == 2)
    }

    @Test("A request while a pass runs owes one more pass instead of cancelling it")
    func requestMidPassOwesARerun() async {
        let schedule = makeSchedule()
        let pass = ScriptedRepairPass(answers: [false, false])
        pass.holdsNextRun = true

        schedule.schedule { await pass.run() }
        await waitUntil { pass.isWaiting } tracking: { _ = pass.isWaiting }
        #expect(schedule.isRunning)
        let running = schedule.task

        schedule.schedule { await pass.run() }
        #expect(schedule.needsRerun)
        #expect(schedule.task == running, "the running pass is not replaced")

        pass.release()
        await running?.value

        #expect(pass.runs == 2)
        #expect(!schedule.needsRerun)
        #expect(!schedule.isRunning)
    }

    @Test("A request while the first pass still waits replaces it")
    func requestDuringDelayReplaces() async {
        var gate: CheckedContinuation<Void, Never>?
        var sleptOnce = false
        let schedule = PostRestrictionRepairSchedule(sleep: { _ in
            if !sleptOnce {
                sleptOnce = true
                await withCheckedContinuation { gate = $0 }
            }
            try Task.checkCancellation()
        })
        let pass = ScriptedRepairPass(answers: [false])

        schedule.schedule { await pass.run() }
        let first = schedule.task
        await Task.yield()
        schedule.schedule { await pass.run() }
        gate?.resume()
        await first?.value
        await schedule.task?.value

        #expect(pass.runs == 1)
    }
}

@MainActor
@Suite("The post-restriction repair brings its picture of the bar into the lane")
struct PostRestrictionReadingTests {
    private let barFrame = CGRect(x: 0, y: 0, width: 200, height: 24)

    private func item(_ title: String, x: CGFloat) -> MenuBarItem {
        ItemsFixture.item(title, x: x, windowID: CGWindowID(100 + Int(x)), ownerPID: 999_991, sourcePID: 999_991)
    }

    /// A bar that is transparent except for an opaque block where `drawn` sits.
    private func capture(drawing drawn: MenuBarItem) throws -> ScreenCapture.MenuBarHostingCapture {
        let image = try ItemsFixture.image(width: Int(barFrame.width), height: Int(barFrame.height), ink: drawn.bounds)
        return ScreenCapture.MenuBarHostingCapture(image: image, windowFrame: barFrame, scale: 1)
    }

    @Test("An item that drew nothing in the picture is blank, and one that drew is not")
    func blankItemsComeFromThePicture() throws {
        let drawn = item("drawn", x: 20)
        let blank = item("blank", x: 120)
        let reading = try PostRestrictionReading(items: [drawn, blank], displayID: 1, barCapture: capture(drawing: drawn))

        #expect(reading.blankTags(among: [drawn, blank]) == [blank.tag])
    }

    @Test("Only the items asked about are judged")
    func onlyAskedItemsAreJudged() throws {
        let drawn = item("drawn", x: 20)
        let blank = item("blank", x: 120)
        let reading = try PostRestrictionReading(items: [drawn, blank], displayID: 1, barCapture: capture(drawing: drawn))

        #expect(reading.blankTags(among: [drawn]).isEmpty)
    }

    @Test("A reading without a picture calls nothing blank")
    func missingPictureCallsNothingBlank() {
        let blank = item("blank", x: 120)
        let reading = PostRestrictionReading(items: [blank], displayID: 1, barCapture: nil)

        #expect(reading.blankTags(among: [blank]).isEmpty)
    }

    @Test("A picture of another display is not used")
    func otherDisplayIsNotCovered() {
        let reading = PostRestrictionReading(items: [], displayID: 1, barCapture: nil)

        #expect(reading.covers(1))
        #expect(!reading.covers(2))
    }
}
