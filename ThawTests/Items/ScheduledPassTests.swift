//
//  ScheduledPassTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A scheduled pass keeps one armed task, what it was asked to do, and its account with the orchestrator")
struct ScheduledPassTests {
    private typealias Pass = ScheduledPass<String>

    /// Arms the pass with a task that stays alive until it is cancelled, standing in for a debounce,
    /// and hands back the task and the turn it was given.
    private func arm(_ pass: inout Pass) -> (task: Task<Void, Never>, turn: Pass.Turn) {
        var armed: (Task<Void, Never>, Pass.Turn)?
        pass.arm { turn in
            let task = Task { _ = try? await Task.sleep(for: .seconds(3600)) }
            armed = (task, turn)
            return task
        }
        guard let armed else { preconditionFailure("arm did not build a task") }
        return armed
    }

    @Test("A new pass holds no task and no intent")
    func startsEmpty() {
        let pass = Pass(.overflowRebalance)

        #expect(pass.work == .overflowRebalance)
        #expect(!pass.isArmed)
        #expect(pass.intent == nil)
    }

    @Test("A request is stamped on the orchestrator under the pass's work and its intent kept")
    func requestStampsAndKeepsIntent() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()

        pass.request("first", cause: .cachePublished, on: repairs)
        pass.request("second", cause: .nativeOverflowChanged, on: repairs)

        #expect(pass.intent == "second")
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance) == [.cachePublished, .nativeOverflowChanged])
        #expect(!pass.isArmed)
    }

    @Test("Arming cancels the task it replaces and keeps the intent")
    func armingReplacesThePredecessor() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()
        pass.request("kept", cause: .cachePublished, on: repairs)
        let first = arm(&pass)

        let second = arm(&pass)
        defer { second.task.cancel() }

        #expect(first.task.isCancelled)
        #expect(!second.task.isCancelled)
        #expect(first.turn != second.turn)
        #expect(pass.isArmed)
        #expect(pass.intent == "kept")
    }

    @Test("The armed task's turn fulfils the intent and leaves the task armed")
    func currentTurnFulfils() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()
        pass.request("asked", cause: .cachePublished, on: repairs)
        let armed = arm(&pass)
        defer { armed.task.cancel() }

        let fulfilled = pass.fulfil(armed.turn)

        #expect(fulfilled)
        #expect(pass.intent == nil)
        #expect(pass.isArmed)
        #expect(!armed.task.isCancelled)
    }

    @Test("A replaced task cannot clear the intent its replacement is waiting to run")
    func replacedTurnCannotFulfil() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()
        pass.request("first", cause: .cachePublished, on: repairs)
        let first = arm(&pass)
        pass.request("merged", cause: .cachePublished, on: repairs)
        let second = arm(&pass)
        defer { second.task.cancel() }

        let fulfilled = pass.fulfil(first.turn)

        #expect(!fulfilled)
        #expect(pass.intent == "merged")
    }

    @Test("The armed task's turn releases the slot without cancelling the task")
    func currentTurnReleases() {
        var pass = Pass(.structuralNormalization)
        let armed = arm(&pass)
        defer { armed.task.cancel() }

        let released = pass.release(armed.turn)

        #expect(released)
        #expect(!pass.isArmed)
        #expect(!armed.task.isCancelled)
    }

    @Test("A released task is not cancelled by the next arming")
    func releasedTaskSurvivesTheNextArming() {
        var pass = Pass(.structuralNormalization)
        let first = arm(&pass)
        defer { first.task.cancel() }
        pass.release(first.turn)

        let second = arm(&pass)
        defer { second.task.cancel() }

        #expect(!first.task.isCancelled)
        #expect(pass.isArmed)
    }

    @Test("A replaced task cannot release its replacement")
    func replacedTurnCannotRelease() {
        var pass = Pass(.structuralNormalization)
        let first = arm(&pass)
        let second = arm(&pass)
        defer { second.task.cancel() }

        let released = pass.release(first.turn)

        #expect(!released)
        #expect(pass.isArmed)
        #expect(!second.task.isCancelled)
    }

    @Test("Cancelling stops the task, drops the intent and withdraws the requests")
    func cancelWithdraws() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()
        pass.request("asked", cause: .cachePublished, on: repairs)
        repairs.request(.structuralNormalization, cause: .userDragEnded)
        let armed = arm(&pass)

        pass.cancel(on: repairs)

        #expect(armed.task.isCancelled)
        #expect(!pass.isArmed)
        #expect(pass.intent == nil)
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance).isEmpty)
        #expect(repairs.ledger.causesWaiting(for: .structuralNormalization) == [.userDragEnded])
    }

    @Test("A cancelled task cannot fulfil or release what was asked after it")
    func cancelledTurnIsStale() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()
        let armed = arm(&pass)
        pass.cancel(on: repairs)
        pass.request("later", cause: .cachePublished, on: repairs)

        let fulfilled = pass.fulfil(armed.turn)
        let released = pass.release(armed.turn)

        #expect(!fulfilled)
        #expect(!released)
        #expect(pass.intent == "later")
    }

    @Test("Cancelling a pass that was never armed still withdraws its requests")
    func cancelUnarmed() {
        var pass = Pass(.overflowRebalance)
        let repairs = RepairOrchestrator()
        pass.request("asked", cause: .cachePublished, on: repairs)

        pass.cancel(on: repairs)

        #expect(pass.intent == nil)
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance).isEmpty)
    }

    // MARK: The overflow rebalance, scheduled through the item manager

    @Test("Scheduling an overflow rebalance arms one task, stamps the cause and keeps the request")
    func overflowRebalanceIsArmed() {
        let manager = MenuBarItemManager()
        defer { manager.overflowRebalance.cancel(on: manager.repairs) }

        manager.scheduleOverflowRebalance(cause: .cachePublished, reason: .externalChange)

        #expect(manager.overflowRebalance.isArmed)
        #expect(manager.overflowRebalance.intent == OverflowRebalanceRequest(reason: .externalChange, immediate: false))
        #expect(manager.repairs.ledger.causesWaiting(for: .overflowRebalance) == [.cachePublished])
    }

    @Test("Overflow rebalance requests coalesce: the explicit reason wins and immediacy sticks")
    func overflowRebalanceRequestsCoalesce() {
        let manager = MenuBarItemManager()
        defer { manager.overflowRebalance.cancel(on: manager.repairs) }

        manager.scheduleOverflowRebalance(cause: .profileApplied, reason: .profileApply)
        manager.scheduleOverflowRebalance(cause: .nativeOverflowChanged, reason: .externalChange, immediate: true)
        manager.scheduleOverflowRebalance(cause: .cachePublished, reason: .externalChange)

        #expect(manager.overflowRebalance.intent == OverflowRebalanceRequest(reason: .profileApply, immediate: true))
        #expect(
            manager.repairs.ledger.causesWaiting(for: .overflowRebalance)
                == [.profileApplied, .nativeOverflowChanged, .cachePublished]
        )
    }
}
