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
    enum Cause: String, CaseIterable, Sendable {
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
        /// A section is about to be revealed, before the restriction is released.
        case revealStarting
        /// The user started ⌘-dragging an icon on the bar.
        case userDragStarted
        /// The user opened an item from the Thaw Bar, search or a hint.
        case userClickedItem
        /// Thaw revealed a section by itself (always-show, zen restore), not the user.
        case policyReveal

        /// Causes that mean someone is at the bar, so the passes they start are not a loop.
        var isUserAction: Bool {
            interruptsAutomaticWork || [.userDragEnded, .userEdit, .sectionRevealed].contains(self)
        }

        /// Causes that mean the user has changed the layout.
        var isLayoutChangeByUser: Bool {
            self == .userDragEnded || self == .userEdit
        }

        /// Causes that call off the automatic passes asked for before them, which were planned on a bar the user is now changing.
        var interruptsAutomaticWork: Bool {
            [.revealStarting, .userDragStarted, .userClickedItem].contains(self)
        }

        /// Causes whose passes keep their turn when the user acts. A policy reveal is not the user,
        /// but the restores it asks for run at user priority, so later input never calls them off.
        var keepsTurnOnUserInput: Bool {
            isUserAction || self == .policyReveal
        }
    }

    private static let diagLog = DiagLog(category: "RepairOrchestrator")

    private(set) var ledger = RepairLedger()
    private let lane = RepairLane()
    private var budget = AutomaticWriteBudget()
    private var interruption = AutomaticPassInterruption()
    /// Writes counted when each automatic pass took the lane, so leaving can say how many it made.
    private var writesAtEntry = [Work: Int]()

    /// How many writers have finished. A plan made at one count is stale at another: something
    /// wrote the bar's order after the plan read it. Every door counts, the unsequenced one too.
    private(set) var writeGeneration: UInt64 = 0

    // MARK: Asking

    /// Told when the user has changed the layout, by a drag or a Layout edit.
    var onUserLayoutChange: (@MainActor () -> Void)?

    /// Stamps a request with what asked for it.
    func request(_ work: Work, cause: Cause) {
        if cause.isLayoutChangeByUser {
            onUserLayoutChange?()
        }
        if cause.interruptsAutomaticWork {
            interruptAutomaticWork(by: cause)
        } else if cause.isUserAction {
            budget.noteUserAction()
        }
        interruption.noteRequest(work, byUser: cause.keepsTurnOnUserInput)
        ledger.request(work, cause: cause)
    }

    /// Drops the requests of work whose scheduler declined to arm it.
    func withdraw(_ work: Work) {
        ledger.withdraw(work)
        interruption.forget(work)
    }

    /// Calls off the automatic passes asked for before this user input.
    /// One still waiting for the lane is turned away; one writing stops at its next check of ``userWorkIsWaiting``.
    func interruptAutomaticWork(by cause: Cause) {
        budget.noteUserAction()
        let calledOff = interruption.noteUserInput()
        let withdrawn = Set(calledOff + lane.dropAutomaticWaiters(where: interruption.isCalledOff))
        for work in withdrawn {
            ledger.withdraw(work)
        }
        let stopping = lane.current.flatMap { interruption.isInterrupted($0) ? $0 : nil }
        guard !withdrawn.isEmpty || stopping != nil else { return }
        let names = withdrawn.map(\.rawValue).sorted().joined(separator: ", ")
        Self.diagLog.info(
            "\(cause.rawValue): user input called off [\(names)]" + (stopping.map { "; \($0.rawValue) stops at its next check" } ?? "")
        )
    }

    // MARK: Taking a turn

    /// Waits for the lane. Call once the work has finished waiting on anything
    /// else and is about to write, and pair with ``leave(_:)``.
    ///
    /// Nil means the task was cancelled while it queued; the caller must return
    /// without writing.
    func enter(_ work: Work, priority: RepairLane.Priority = .automatic) async -> RepairLane.Hold? {
        guard priority == .user || budget.allowsAutomaticWrites() else {
            withdraw(work)
            Self.diagLog.debug("\(work.rawValue): automatic writes are paused; not running")
            return nil
        }
        guard priority == .user || !interruption.isCalledOff(work) else {
            withdraw(work)
            Self.diagLog.debug("\(work.rawValue): called off by user input; not running")
            return nil
        }
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
        if priority == .automatic {
            writesAtEntry[work] = StoreWriteAudit.totalWrites
            interruption.noteStarted(work)
        }
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
    /// User input that arrived after the automatic pass in the lane started counts too.
    var userWorkIsWaiting: Bool {
        lane.userWorkIsWaiting || lane.current.map(interruption.isInterrupted) == true
    }

    func leave(_ hold: RepairLane.Hold) {
        let ran = ledger.end(hold.work)
        writeGeneration &+= 1
        interruption.noteFinished(hold.work)
        lane.leave(hold)
        Self.diagLog.debug("\(hold.work.rawValue): finished after \(ran)")
        guard let entry = writesAtEntry.removeValue(forKey: hold.work) else { return }
        let writes = StoreWriteAudit.totalWrites - entry
        Self.diagLog.info("\(hold.work.rawValue): pass made \(writes) write(s) in \(ran)")
        if writes > 0, budget.noteWritingPass() {
            Self.diagLog.warning(
                "automatic writes paused for \(AutomaticWriteBudget.pause): over \(AutomaticWriteBudget.limit) writing passes " +
                    "in \(AutomaticWriteBudget.window) with no user action"
            )
        }
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
