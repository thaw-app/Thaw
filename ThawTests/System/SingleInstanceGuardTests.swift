//
//  SingleInstanceGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// What launch does with the rule's decision, with every live effect replaced.
@MainActor
@Suite("Single instance guard")
struct SingleInstanceGuardTests {
    private typealias Guard = SingleInstanceGuard

    private final class Log {
        var events: [String] = []
    }

    private let other = SingleInstanceRule.RunningProcess(
        processIdentifier: 42,
        parentProcessIdentifier: 1,
        bundleIdentifier: "com.stonerl.Thaw.debug",
        localizedName: "Thaw Debug"
    )

    private func actions(_ log: Log, choice: Guard.Choice, stops: Bool, retakes: Bool = true) -> Guard.Actions {
        Guard.Actions(
            ask: { log.events.append("ask \($0.map(\.processIdentifier))"); return choice },
            stop: { log.events.append("stop \($0.map(\.processIdentifier))"); return stops },
            retakeLock: { log.events.append("lock"); return retakes },
            reportFailure: { _ in log.events.append("report") },
            quitThisCopy: { log.events.append("quit") }
        )
    }

    private func ask(_ others: [SingleInstanceRule.RunningProcess], held: Bool = false) -> SingleInstanceRule.Decision {
        .ask(others: others, lockHeldElsewhere: held)
    }

    @Test("Launch goes on without asking when no other copy runs")
    func proceedAsksNothing() {
        let log = Log()
        #expect(Guard.resolve(.proceed, actions: actions(log, choice: .quitThisCopy, stops: true)))
        #expect(log.events.isEmpty)
    }

    @Test("Choosing to quit this copy quits it and leaves the other alone")
    func quitThisCopy() {
        let log = Log()
        #expect(!Guard.resolve(ask([other]), actions: actions(log, choice: .quitThisCopy, stops: true)))
        #expect(log.events == ["ask [42]", "quit"])
    }

    @Test("Choosing to quit the other copy stops it and goes on")
    func quitOtherCopy() {
        let log = Log()
        #expect(Guard.resolve(ask([other]), actions: actions(log, choice: .quitOtherCopies, stops: true)))
        #expect(log.events == ["ask [42]", "stop [42]"])
    }

    @Test("When the other copy will not stop, this copy says so and quits")
    func otherCopyWontStop() {
        let log = Log()
        #expect(!Guard.resolve(ask([other]), actions: actions(log, choice: .quitOtherCopies, stops: false)))
        #expect(log.events == ["ask [42]", "stop [42]", "report", "quit"])
    }

    @Test("When only the lock shows another copy, quitting it waits for the lock")
    func lockOnlyCopy() {
        let log = Log()
        #expect(Guard.resolve(ask([], held: true), actions: actions(log, choice: .quitOtherCopies, stops: false)))
        #expect(log.events == ["ask []", "lock"])
        let refused = Log()
        #expect(!Guard.resolve(
            ask([], held: true),
            actions: actions(refused, choice: .quitOtherCopies, stops: true, retakes: false)
        ))
        #expect(refused.events == ["ask []", "lock", "report", "quit"])
    }

    @Test("A copy holding the lock is stopped before the lock is taken again")
    func stopThenRetakeLock() {
        let log = Log()
        #expect(Guard.resolve(ask([other], held: true), actions: actions(log, choice: .quitOtherCopies, stops: true)))
        #expect(log.events == ["ask [42]", "stop [42]", "lock"])
        let stuck = Log()
        #expect(!Guard.resolve(ask([other], held: true), actions: actions(stuck, choice: .quitOtherCopies, stops: false)))
        #expect(stuck.events == ["ask [42]", "stop [42]", "report", "quit"])
    }

    @Test("Waiting for the lock stops once it is taken, and gives up after the last poll")
    func waitForLock() {
        var attempts = 0
        var pauses = 0
        let taken = Guard.waitForLock(polls: 10, pause: { pauses += 1 }) {
            attempts += 1
            return attempts < 3 ? .heldElsewhere : .acquired
        }
        #expect(taken == .acquired)
        #expect(attempts == 3)
        #expect(pauses == 2)

        pauses = 0
        #expect(Guard.waitForLock(polls: 4, pause: { pauses += 1 }) { .heldElsewhere } == .heldElsewhere)
        #expect(pauses == 4)
        #expect(Guard.waitForLock(polls: 0, pause: {}) { .heldElsewhere } == .heldElsewhere)
        #expect(Guard.waitForLock(polls: 5, pause: { Issue.record("No wait without a holder") }) { .unavailable } == .unavailable)
    }

    @Test("The prompt's words follow how many copies it names")
    func promptWording() {
        let none = SingleInstancePrompt(.unnamed, appName: "Thaw")
        #expect(none.title == "Another Copy of Thaw Is Running")
        #expect(none.continueButton == "Quit It and Continue")
        #expect(none.failureTitle == "Couldn’t Quit the Other Copy")

        let one = SingleInstancePrompt(.one("Thaw Debug"), appName: "Thaw")
        #expect(one.title == "Thaw Debug Is Already Running")
        #expect(one.message.contains("quit Thaw Debug and continue"))
        #expect(one.continueButton == "Quit Thaw Debug and Continue")
        #expect(one.failureTitle == "Couldn’t Quit Thaw Debug")

        let several = SingleInstancePrompt(.several(["Thaw", "Thaw Debug"]), appName: "Thaw")
        #expect(several.title == "Other Copies of Thaw Are Running")
        #expect(several.message.hasPrefix("Thaw and Thaw Debug are running."))
        #expect(several.continueButton == "Quit Them and Continue")
        #expect(several.failureTitle == "Couldn’t Quit the Other Copies")
        #expect(several.failureMessage.hasPrefix("Thaw and Thaw Debug didn’t quit"))
    }

    @Test("A copy that quits when asked is never forced")
    func gracefulStop() {
        var running: Set<pid_t> = [1, 2]
        var forced: [pid_t] = []
        let stopped = Guard.stop(
            [1, 2],
            terminate: { running.remove($0) },
            forceTerminate: { forced.append($0) },
            isRunning: { running.contains($0) },
            pause: {}
        )
        #expect(stopped)
        #expect(forced.isEmpty)
    }

    @Test("A copy still running after the grace period is forced")
    func forcedStop() {
        var running: Set<pid_t> = [1, 2]
        var pauses = 0
        var forced: [pid_t] = []
        let stopped = Guard.stop(
            [1, 2],
            terminate: { if $0 == 1 { running.remove($0) } },
            forceTerminate: { forced.append($0); running.remove($0) },
            isRunning: { running.contains($0) },
            pause: { pauses += 1 }
        )
        #expect(stopped)
        #expect(forced == [2])
        #expect(pauses == Guard.gracefulPolls)
    }

    @Test("A copy that survives a forced quit is reported")
    func unstoppable() {
        var pauses = 0
        let stopped = Guard.stop(
            [7],
            terminate: { _ in },
            forceTerminate: { _ in },
            isRunning: { _ in true },
            pause: { pauses += 1 }
        )
        #expect(!stopped)
        #expect(pauses == Guard.gracefulPolls + Guard.forcedPolls)
    }

    @Test("The test host neither asks nor takes the instance lock")
    func liveEnforceInTestHost() {
        #expect(Guard.enforce())
        #expect(!Guard.holdsInstanceLock)
    }
}
