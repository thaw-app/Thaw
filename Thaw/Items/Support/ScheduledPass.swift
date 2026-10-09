//
//  ScheduledPass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// One kind of repair pass, armed to run later: the task that waits to run it, what the next run
/// was asked to do, and its account with the ``RepairOrchestrator``.
///
/// A scheduler arms a task, and a later request replaces it. Two rules follow, and both live here
/// so that no scheduler has to remember them. A task that was replaced or cancelled must not clear
/// what its replacement is waiting to do: each armed task is given a ``Turn``, and only the latest
/// turn can ``fulfil(_:)`` the intent or ``release(_:)`` the slot. And the orchestrator's account
/// must follow the task: a request is stamped as its intent is kept, and a cancelled pass withdraws
/// what was asked of it.
///
/// The pass does not wait and does not write. The task it holds does both, in the scheduler's own
/// words, so each scheduler keeps its debounce, its checks and its place in the lane.
///
/// `Intent` is what a run needs to know about the requests it absorbed. A pass with nothing to
/// remember between requests uses `Never`.
@MainActor
struct ScheduledPass<Intent> {
    /// Proof of being the task armed most recently. A task whose turn is no longer current was
    /// replaced or cancelled.
    struct Turn: Equatable, Sendable {
        fileprivate let number: UInt64
    }

    let work: RepairOrchestrator.Work

    /// What the next run was asked to do. Kept until the run that honours it says so, so a task
    /// cancelled on the way leaves it for its replacement.
    private(set) var intent: Intent?

    private var task: Task<Void, Never>?
    private var currentTurn: UInt64 = 0

    init(_ work: RepairOrchestrator.Work) {
        self.work = work
    }

    /// Whether a task holds the slot. It may be waiting, running, or already over.
    var isArmed: Bool {
        task != nil
    }

    /// Stamps a request on the orchestrator and keeps what it asks for. The caller folds the intent
    /// already waiting into the new one, since how requests merge is the pass kind's own policy.
    mutating func request(_ intent: Intent, cause: RepairOrchestrator.Cause, on repairs: RepairOrchestrator) {
        repairs.request(work, cause: cause)
        self.intent = intent
    }

    /// Cancels the task in the slot and arms the one `makeTask` builds. The new task gets its turn
    /// to present when it is done. The requests and the intent stand: they are the new task's to run.
    mutating func arm(_ makeTask: (Turn) -> Task<Void, Never>) {
        task?.cancel()
        currentTurn &+= 1
        task = makeTask(Turn(number: currentTurn))
    }

    /// Notes that the task's run honoured everything asked so far. The task stays in the slot, so a
    /// later request still cancels what it has left to do. False, and nothing changes, when the turn
    /// is no longer current.
    @discardableResult
    mutating func fulfil(_ turn: Turn) -> Bool {
        guard turn.number == currentTurn else { return false }
        intent = nil
        return true
    }

    /// Gives up the slot without cancelling the task, so the next arming does not cancel it. For a
    /// task that has finished waiting and must not be interrupted while it writes, or one that is
    /// over. False, and nothing changes, when the turn is no longer current.
    @discardableResult
    mutating func release(_ turn: Turn) -> Bool {
        guard turn.number == currentTurn else { return false }
        task = nil
        return true
    }

    /// Calls the pass off: cancels and drops the task, drops the intent, and withdraws the requests
    /// from the orchestrator so they are not credited to a later, unrelated run.
    mutating func cancel(on repairs: RepairOrchestrator) {
        task?.cancel()
        task = nil
        currentTurn &+= 1
        intent = nil
        repairs.withdraw(work)
    }
}
