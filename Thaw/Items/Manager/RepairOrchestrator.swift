//
//  RepairOrchestrator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// The front door for work that rewrites the bar's order.
///
/// Callers say what they want done and why (``request(_:cause:)``), wait their
/// turn (``enter(_:priority:)``), write, and hand the turn back
/// (``leave(_:)``). The orchestrator keeps the account in a ``RepairLedger``
/// and the queue in a ``RepairLane``, and logs what each run stood for.
///
/// It decides order, not content: what a piece of work writes is its own
/// business.
@MainActor
final class RepairOrchestrator {
    /// A piece of work that writes the bar's order and takes the lane to do it.
    enum Work: String, CaseIterable, Sendable {
        case structuralNormalization
        case postRestrictionRepair
        case overflowRebalance
        case deferredLayoutReconcile
        case arrivalOrderRestore
        /// An order the user authored: a pane drop, a keyboard move, a sort,
        /// a group edit.
        case authoredOrderApply
        /// A profile's sections and order being put on the bar.
        case profileLayoutApply
        /// The once-a-launch pruning of dead rows.
        case storeHygiene
        /// The settled restore a reveal owes the bar: boundary, control order,
        /// then the revealed sections' authored order.
        case revealReconcile
        /// Pinning the visible order just before a section is revealed.
        case preRevealOrder
        /// A concealed section's weights, written for a Layout edit in Manual.
        case manualLayoutEdit
        /// One item moved, or a set of items seated in a section, inside the move permit.
        case itemMove
    }

    /// What asked for a piece of work.
    enum Cause: String, Sendable {
        /// The user finished ⌘-dragging an icon on the bar.
        case userDragEnded
        /// A move Thaw made was honoured and needs pinning as weights.
        case moveFulfilled
        /// An ambient cache pass found the control items or Siri out of order.
        case structuralDriftObserved
        /// A structural write was put off because a reveal or hide was in flight.
        case revealHideTransition
        /// A startup, relaunch, or display settling period ended.
        case settled
        /// The restriction was torn down and rebuilt, reflowing the bar.
        case restrictionChanged
        /// A cache pass published a new inventory.
        case cachePublished
        /// The system's own overflow control appeared or changed.
        case nativeOverflowChanged
        /// A newly arrived item shuffled the recorded Visible order.
        case arrivalDisturbedOrder
        /// A saved-layout apply was declined by a guard that expires.
        case layoutApplyBlocked
        /// The work woke at a bad moment and asked for itself again.
        case rearmed
        /// The user arranged items in Layout.
        case userEdit
        /// A profile was picked, or switched to by display, Space or Focus.
        case profileApplied
        /// A setting that reshapes the bar was changed.
        case settingChanged
        /// A section was revealed, or is about to be.
        case sectionRevealed
    }

    private static let diagLog = DiagLog(category: "RepairOrchestrator")

    private(set) var ledger = RepairLedger()
    private let lane = RepairLane()

    /// How many writers have finished. A plan made at one count is stale at another: something
    /// wrote the bar's order after the plan read it. Every door counts, the unsequenced one too.
    private(set) var writeGeneration: UInt64 = 0

    // MARK: Asking

    /// Stamps a request with what asked for it.
    func request(_ work: Work, cause: Cause) {
        ledger.request(work, cause: cause)
    }

    /// Drops the requests of work whose scheduler declined to arm it.
    func withdraw(_ work: Work) {
        ledger.withdraw(work)
    }

    // MARK: Taking a turn

    /// Waits for the lane. Call once the work has finished waiting on anything
    /// else and is about to write, and pair with ``leave(_:)``.
    ///
    /// Nil means the task was cancelled while it queued; the caller must return
    /// without writing.
    func enter(_ work: Work, priority: RepairLane.Priority = .automatic) async -> RepairLane.Hold? {
        let queuedAt = ContinuousClock.now
        let ahead = lane.current
        let takeoversBefore = lane.takeovers
        guard let hold = await lane.enter(work, priority: priority) else {
            Self.diagLog.debug("\(work.rawValue): superseded while queued")
            return nil
        }
        if lane.takeovers != takeoversBefore {
            Self.diagLog.error(
                "\(work.rawValue): took the lane from \(ahead?.rawValue ?? "unknown work"),"
                    + " which held it for over \(RepairLane.staleAfter)"
            )
        }
        let run = ledger.begin(work)
        let queued = ahead.map { ", queued \(queuedAt.duration(to: .now)) behind \($0.rawValue)" } ?? ""
        Self.diagLog.debug("\(work.rawValue): running for \(describe(run))\(queued)")
        return hold
    }

    /// Takes the lane for an order the user just authored, ahead of every
    /// automatic pass that is waiting.
    func enterForUserEdit() async -> RepairLane.Hold? {
        request(.authoredOrderApply, cause: .userEdit)
        return await enter(.authoredOrderApply, priority: .user)
    }

    /// Hands the lane to whoever is next.
    /// Whether user work is queued behind the pass in the lane. See
    /// ``RepairLane/userWorkIsWaiting``.
    var userWorkIsWaiting: Bool {
        lane.userWorkIsWaiting
    }

    func leave(_ hold: RepairLane.Hold) {
        let ran = ledger.end(hold.work)
        writeGeneration &+= 1
        lane.leave(hold)
        Self.diagLog.debug("\(hold.work.rawValue): finished after \(ran)")
    }

    /// Runs a write that is one synchronous step.
    ///
    /// Such a write cannot wait its turn, and cannot itself be interleaved. It
    /// takes the lane when nobody holds it. When another piece of work is in
    /// the middle of its own writes, this one still runs, between that work's
    /// steps, and its permit says so.
    func writeNow<Result>(
        _ work: Work,
        cause: Cause,
        _ write: (borrowing StoreWritePermit) -> Result
    ) -> Result {
        request(work, cause: cause)
        guard let hold = lane.enterIfFree(work) else {
            withdraw(work)
            let holder = lane.current?.rawValue ?? "unknown work"
            defer { writeGeneration &+= 1 }
            return write(.unsequenced("\(work.rawValue) while \(holder) was writing"))
        }
        _ = ledger.begin(work)
        defer {
            ledger.end(work)
            writeGeneration &+= 1
            lane.leave(hold)
        }
        return write(StoreWritePermit(hold))
    }

    // MARK: Single moves

    /// Takes the lane for a single move when nobody holds it, so no pass starts while the move is writing.
    /// Call inside the move permit and pair with ``endMove(_:)``.
    ///
    /// Nil means the lane was busy and the move runs anyway. The holder may be the very pass that asked for
    /// this move, and the lane cannot tell that pass from another, so a move never waits for it.
    func beginMove() -> RepairLane.Hold? {
        let hold = lane.enterIfFree(.itemMove)
        _ = ledger.begin(.itemMove)
        return hold
    }

    func endMove(_ hold: RepairLane.Hold?) {
        guard let hold else {
            ledger.end(.itemMove)
            writeGeneration &+= 1
            return
        }
        leave(hold)
    }

    // MARK: Work that stays outside the lane

    /// Marks unlaned work as running and reports any laned work still writing.
    /// Pair with ``end(_:)``.
    func begin(_ work: Work) {
        let run = ledger.begin(work)
        let others = run.overlapping.map(\.rawValue).joined(separator: ", ")
        Self.diagLog.debug(
            "\(work.rawValue): running for \(describe(run))" + (others.isEmpty ? "" : ", alongside \(others)")
        )
    }

    func end(_ work: Work) {
        // Ended outside the message: a log line that is switched off never evaluates its text.
        let ran = ledger.end(work)
        Self.diagLog.debug("\(work.rawValue): finished after \(ran)")
    }

    private func describe(_ run: RepairLedger.Run) -> String {
        "\(run.causeSummary) (\(run.requests) request(s), waited \(run.waited))"
    }
}
