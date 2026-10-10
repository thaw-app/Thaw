//
//  RepairLane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Makes the automatic repair passes follow one another.
///
/// Each pass writes the same position table and re-applies the same
/// restriction, and each suspends between its writes. Run from separate tasks
/// they interleave: one pass plans against an order the other is half way
/// through changing. The lane admits one pass at a time, in the order they
/// asked, so every pass reads a bar the previous one has finished with.
///
/// Only the writing part of a pass belongs in the lane. A pass that holds it
/// through its debounce or its settle waits makes the others late for nothing.
///
/// Work the user asked for waits only for the pass that is writing right now,
/// never for the automatic passes queued behind it. A single-item move keeps
/// its own permit and takes the lane only when it finds it free.
@MainActor
final class RepairLane {
    /// Proof of admission; hand it back to ``leave(_:)``.
    struct Hold: Equatable {
        let work: RepairOrchestrator.Work
        fileprivate let token: UInt64
    }

    /// Who is waiting. Decides the place in line, not who may enter.
    enum Priority: Sendable {
        /// The user asked for this and is watching for it.
        case user
        /// Thaw decided to do this on its own.
        case automatic
    }

    /// How long one pass may hold the lane before the next takes it over. No
    /// pass comes near this; it is there so a pass that never returns cannot
    /// stop every later repair for the rest of the session.
    static nonisolated let staleAfter: Duration = .seconds(30)

    private struct Waiter {
        let hold: Hold
        let priority: Priority
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var holder: Hold?
    private var heldSince: ContinuousClock.Instant?
    private var waiters: [Waiter] = [] // user work first, each kind in the order it asked
    private var nextToken: UInt64 = 0
    private(set) var takeovers = 0

    /// The pass in the lane right now.
    var current: RepairOrchestrator.Work? {
        holder?.work
    }

    /// Passes queued behind the holder, first in line first.
    var queued: [RepairOrchestrator.Work] {
        waiters.map(\.hold.work)
    }

    /// Whether something the user asked for is in line. An automatic pass
    /// that has not written yet checks this and steps aside.
    var userWorkIsWaiting: Bool {
        waiters.contains { $0.priority == .user }
    }

    /// Waits for the lane. Returns nil when the task was cancelled while it
    /// queued, which is how a superseded pass drops out of line.
    func enter(
        _ work: RepairOrchestrator.Work,
        priority: Priority = .automatic,
        at now: ContinuousClock.Instant = .now
    ) async -> Hold? {
        guard !Task.isCancelled else { return nil }
        nextToken += 1
        let hold = Hold(work: work, token: nextToken)
        if let heldSince, heldSince.duration(to: now) > Self.staleAfter {
            // The holder never came back. Its eventual leave() carries an old
            // token and is ignored.
            takeovers += 1
            admit(hold, at: now)
            return hold
        }
        guard holder != nil else {
            admit(hold, at: now)
            return hold
        }
        let admitted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enqueue(Waiter(hold: hold, priority: priority, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(hold)
            }
        }
        guard admitted else { return nil }
        // Cancelled in the same turn it was admitted: give the lane straight back.
        guard !Task.isCancelled else {
            leave(hold)
            return nil
        }
        return hold
    }

    /// Takes the lane only if nobody holds it, without waiting. For a write
    /// made in one synchronous step, which cannot suspend to queue.
    func enterIfFree(
        _ work: RepairOrchestrator.Work,
        at now: ContinuousClock.Instant = .now
    ) -> Hold? {
        guard holder == nil else { return nil }
        nextToken += 1
        let hold = Hold(work: work, token: nextToken)
        admit(hold, at: now)
        return hold
    }

    /// Hands the lane to the next pass in line.
    func leave(_ hold: Hold) {
        guard holder == hold else { return }
        guard !waiters.isEmpty else {
            holder = nil
            heldSince = nil
            return
        }
        let next = waiters.removeFirst()
        admit(next.hold, at: .now)
        next.continuation.resume(returning: true)
    }

    /// User work goes behind the user work already waiting and ahead of every
    /// automatic pass.
    private func enqueue(_ waiter: Waiter) {
        guard waiter.priority == .user,
              let firstAutomatic = waiters.firstIndex(where: { $0.priority == .automatic })
        else {
            waiters.append(waiter)
            return
        }
        waiters.insert(waiter, at: firstAutomatic)
    }

    private func admit(_ hold: Hold, at now: ContinuousClock.Instant) {
        holder = hold
        heldSince = now
    }

    private func cancelWaiter(_ hold: Hold) {
        guard let index = waiters.firstIndex(where: { $0.hold == hold }) else {
            // Already admitted; enter() notices the cancellation and leaves.
            return
        }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
