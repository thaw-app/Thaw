//
//  MoveGatePreflightTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Move-gate preflight", .serialized)
struct MoveGatePreflightTests {
    typealias EventError = MenuBarItemManager.EventError

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
}
