//
//  SettlingWaitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Settling wait", .timeLimit(.minutes(1)))
struct SettlingWaitTests {
    @MainActor
    private final class Settling {
        var isSettling = false
        var task: Task<Void, Never>?
        var reads = 0
    }

    @Test("Returns at once when nothing is settling")
    func returnsWhenNotSettling() async {
        let settling = Settling()
        settling.task = Task {}

        await SettlingWait.follow(isSettling: { settling.isSettling }, currentTask: { settling.task })

        #expect(settling.isSettling == false)
    }

    @Test("Returns at once when the settle has no task")
    func returnsWithoutTask() async {
        let settling = Settling()
        settling.isSettling = true

        await SettlingWait.follow(isSettling: { settling.isSettling }, currentTask: { settling.task })

        #expect(settling.isSettling)
    }

    @Test("Waits for the task to finish")
    func waitsForTask() async {
        let settling = Settling()
        settling.isSettling = true
        settling.task = Task { @MainActor in
            await Task.yield()
            settling.isSettling = false
        }

        await SettlingWait.follow(isSettling: { settling.isSettling }, currentTask: { settling.task })

        #expect(!settling.isSettling)
    }

    @Test("Follows a task that a later settle put in its place")
    func followsReplacement() async {
        let settling = Settling()
        var replacementFinished = false
        let replacement = Task { @MainActor in
            await Task.yield()
            await Task.yield()
            replacementFinished = true
            settling.isSettling = false
        }
        settling.isSettling = true
        settling.task = Task { @MainActor in
            await Task.yield()
            settling.task = replacement
        }

        await SettlingWait.follow(isSettling: { settling.isSettling }, currentTask: { settling.task })

        #expect(replacementFinished)
    }

    @Test("Returns once the task has finished, even when the flag stays set")
    func returnsAfterFinishedTask() async {
        let settling = Settling()
        settling.isSettling = true
        let task = Task<Void, Never> {}
        await task.value
        settling.task = task

        await SettlingWait.follow(
            isSettling: {
                settling.reads += 1
                return settling.isSettling
            },
            currentTask: { settling.task }
        )

        #expect(settling.reads == 1, "A finished task is not awaited again")
    }

    @Test("A cancelled caller does not wait")
    func cancelledCallerDoesNotWait() async {
        let settling = Settling()
        settling.isSettling = true
        settling.task = Task { @MainActor in
            while settling.isSettling {
                await Task.yield()
            }
        }
        defer { settling.isSettling = false }

        let waiter = Task { @MainActor in
            await SettlingWait.follow(isSettling: { settling.isSettling }, currentTask: { settling.task })
        }
        waiter.cancel()
        await waiter.value

        #expect(settling.isSettling, "The waiter returned while the settle was still running")
    }
}
