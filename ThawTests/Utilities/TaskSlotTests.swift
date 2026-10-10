//
//  TaskSlotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Task slot")
struct TaskSlotTests {
    @Test("A replacement stales the old ticket and keeps the new one current")
    func replacementSupersedes() async {
        let slot = TaskSlot()
        let first = Gate()
        let second = Gate()
        var tickets: [TaskSlot.Ticket] = []

        slot.replace { ticket in
            tickets.append(ticket)
            await first.wait()
        }
        await first.waitUntilEntered()

        slot.replace { ticket in
            tickets.append(ticket)
            await second.wait()
        }
        await second.waitUntilEntered()

        #expect(tickets.count == 2)
        #expect(slot.isCurrent(tickets[1]))
        #expect(!slot.isCurrent(tickets[0]))

        first.open()
        second.open()
        await slot.waitUntilFinished()
        #expect(!slot.isRunning)
    }

    @Test("A superseded operation's late write is rejected by isCurrent")
    func staleWriteIsRejected() async {
        let slot = TaskSlot()
        let first = Gate()
        var writes: [String] = []

        slot.replace { ticket in
            await first.wait()
            if slot.isCurrent(ticket) {
                writes.append("first")
            }
        }
        await first.waitUntilEntered()

        slot.replace { ticket in
            if slot.isCurrent(ticket) {
                writes.append("second")
            }
        }
        first.open()
        await slot.waitUntilFinished()

        #expect(writes == ["second"])
    }

    @Test("Cancel stales the ticket and clears the running slot")
    func cancelStopsWork() async throws {
        let slot = TaskSlot()
        let gate = Gate()
        var ticket: TaskSlot.Ticket?

        slot.replace { current in
            ticket = current
            await gate.wait()
        }
        await gate.waitUntilEntered()
        #expect(slot.isRunning)

        slot.cancel()
        #expect(!slot.isRunning)
        #expect(try !slot.isCurrent(#require(ticket)))

        gate.open()
        await Task.yield()
    }

    @Test("A superseded operation finishing does not clear the newer slot")
    func supersededFinishLeavesReplacementRunning() async throws {
        let slot = TaskSlot()
        let first = Gate()
        let current = Gate()
        let (supersededFinished, supersededFinishedContinuation) = AsyncStream<Void>.makeStream()
        var currentTicket: TaskSlot.Ticket?

        slot.replace { _ in
            await first.wait()
            supersededFinishedContinuation.yield(())
        }
        slot.replace { ticket in
            currentTicket = ticket
            await current.wait()
        }
        await current.waitUntilEntered()

        first.open()
        var finished = supersededFinished.makeAsyncIterator()
        _ = await finished.next()
        await Task.yield()

        #expect(slot.isRunning)
        #expect(try slot.isCurrent(#require(currentTicket)))

        current.open()
        await slot.waitUntilFinished()
        #expect(!slot.isRunning)
    }

    @Test("waitUntilFinished follows a replacement scheduled while waiting")
    func waitUntilFinishedFollowsReplacement() async {
        let slot = TaskSlot()
        let first = Gate()
        let second = Gate()
        var completed: [Int] = []

        slot.replace { _ in
            await first.wait()
            completed.append(1)
        }
        await first.waitUntilEntered()

        let waiting = Task { await slot.waitUntilFinished() }

        slot.replace { _ in
            await second.wait()
            completed.append(2)
        }
        await second.waitUntilEntered()

        first.open()
        await Task.yield()
        second.open()
        await waiting.value

        #expect(completed == [1, 2])
        #expect(!slot.isRunning)
    }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var entry: CheckedContinuation<Void, Never>?
    private var exit: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            exit = continuation
            entry?.resume()
            entry = nil
        }
    }

    func waitUntilEntered() async {
        if exit != nil || isOpen {
            return
        }
        await withCheckedContinuation { entry = $0 }
    }

    func open() {
        isOpen = true
        exit?.resume()
        exit = nil
    }
}
