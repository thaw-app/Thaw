//
//  MoveGatePreflightTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import os.lock
import Testing
@testable import Thaw

@MainActor
@Suite("Move-gate preflight", .serialized)
struct MoveGatePreflightTests {
    typealias EventError = MenuBarItemManager.EventError
    typealias ScheduledAction = @Sendable () -> Void

    private func item(windowID: CGWindowID, title: String) -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.MoveGatePreflight", title: title),
            windowID: windowID
        )
    }

    /// A manager without AppState cannot perform any live move. Reaching the
    /// preflight's named error instead proves that the one-shot gate-owned
    /// check runs before the mover touches AppState or WindowServer state.
    @Test("A rejected gate-owned preflight stops before live move work")
    func rejectedPreflightStopsBeforeLiveMoveWork() async {
        let manager = MenuBarItemManager()
        let movedItem = item(windowID: 41, title: "Moved")
        let targetItem = item(windowID: 42, title: "Target")
        var events = [String]()

        do {
            try await manager.move(
                item: movedItem,
                to: .leftOfItem(targetItem),
                options: .init(
                    shouldBegin: {
                        events.append("preflight")
                        return false
                    },
                    didFinishWhileHoldingGate: {
                        events.append("finish")
                    }
                )
            )
            Issue.record("Expected the rejected preflight to throw moveSuperseded")
        } catch let error as EventError {
            guard case .moveSuperseded = error else {
                Issue.record("Expected moveSuperseded, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected EventError.moveSuperseded, got \(error)")
        }

        #expect(events == ["preflight", "finish"])
    }

    /// The semaphore is intentionally private. Exercise the exact exit helper
    /// instead so this assertion has no scheduler or timing dependency.
    @Test("Batch timestamp ownership updates before the move gate is released")
    func finishRunsBeforeRelease() {
        var events = [String]()

        MenuBarItemManager.performMoveGateExitActions(
            didFinishWhileHoldingGate: {
                events.append("finish")
            },
            releaseGate: {
                events.append("release")
            }
        )

        #expect(events == ["finish", "release"])
    }

    @Test("Press-release deadlines are bounded")
    func pressReleaseDeadlinesAreBounded() {
        #expect(MenuBarItemManager.pressReleaseDeadline(for: .milliseconds(100)) == .milliseconds(1500))
        #expect(MenuBarItemManager.pressReleaseDeadline(for: .milliseconds(350)) == .milliseconds(2100))
        #expect(MenuBarItemManager.pressReleaseDeadline(for: .seconds(1)) == .seconds(3))
    }

    @Test("A confirmed mouse-up cancels the safety release")
    func confirmedMouseUpCancelsSafetyRelease() {
        let scheduled = OSAllocatedUnfairLock<ScheduledAction?>(initialState: nil)
        let safetyPosts = OSAllocatedUnfairLock(initialState: 0)
        let guardState = MenuBarItemManager.PressReleaseGuard(
            deadline: .seconds(1),
            item: item(windowID: 51, title: "Moved"),
            scheduler: { _, action in scheduled.withLock { $0 = action } },
            postSafetyRelease: { safetyPosts.withLock { $0 += 1 } }
        )

        guardState.arm()
        guardState.recordReleaseAttempt(delivered: true)
        scheduled.withLock { $0 }?()

        #expect(guardState.state == .releaseConfirmed)
        #expect(safetyPosts.withLock { $0 } == 0)
    }

    @Test("Failed mouse-ups leave the safety release armed")
    func failedMouseUpsKeepSafetyReleaseArmed() {
        let scheduled = OSAllocatedUnfairLock<ScheduledAction?>(initialState: nil)
        let safetyPosts = OSAllocatedUnfairLock(initialState: 0)
        let guardState = MenuBarItemManager.PressReleaseGuard(
            deadline: .seconds(1),
            item: item(windowID: 52, title: "Moved"),
            scheduler: { _, action in scheduled.withLock { $0 = action } },
            postSafetyRelease: { safetyPosts.withLock { $0 += 1 } }
        )

        guardState.arm()
        guardState.recordReleaseAttempt(delivered: false)
        guardState.recordReleaseAttempt(delivered: false)
        #expect(guardState.state == .armed)

        scheduled.withLock { $0 }?()
        #expect(guardState.state == .fired)
        #expect(safetyPosts.withLock { $0 } == 1)
    }

    @Test("Pre-gate waiting does not retain the move permit")
    func inputWaitingDoesNotRetainMovePermit() async throws {
        let firstWaitStarted = MoveTestLatch()
        let releaseFirstWait = MoveTestLatch()
        let secondBodyEntered = MoveTestLatch()
        let releaseSecondBody = MoveTestLatch()
        var events = [String]()

        let first = Task { @MainActor in
            try await MenuBarItemManager.performWithMoveGate(
                timeout: .seconds(5),
                waitBeforeGate: {
                    events.append("first-wait")
                    await firstWaitStarted.open()
                    await releaseFirstWait.wait()
                },
                operation: { events.append("first-body") }
            )
        }

        await firstWaitStarted.wait()
        let second = Task { @MainActor in
            try await MenuBarItemManager.performWithMoveGate(
                timeout: .seconds(5),
                operation: {
                    events.append("second-body")
                    await secondBodyEntered.open()
                    await releaseSecondBody.wait()
                }
            )
        }

        await secondBodyEntered.wait()
        await releaseFirstWait.open()
        await releaseSecondBody.open()
        try await second.value
        try await first.value

        #expect(events == ["first-wait", "second-body", "first-body"])
    }
}

private actor MoveTestLatch {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else {
            return
        }
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}
