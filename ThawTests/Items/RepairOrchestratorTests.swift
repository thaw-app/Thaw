//
//  RepairOrchestratorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("The orchestrator gives each writer its turn and its permit")
struct RepairOrchestratorTests {
    @Test("A synchronous write takes the lane when it is free and gives it straight back")
    func writeNowOnAFreeLane() async throws {
        let repairs = RepairOrchestrator()

        let door = repairs.writeNow(.preRevealOrder, cause: .sectionRevealed) { permit in
            permit.door
        }

        #expect(door == .repairLane(.preRevealOrder))
        #expect(!repairs.ledger.isRunning(.preRevealOrder))
        let next = try #require(await repairs.enter(.structuralNormalization))
        repairs.leave(next)
    }

    @Test("A synchronous write still runs while other work holds the lane, and says whose writes it fell between")
    func writeNowOnAHeldLane() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        let door = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { permit in
            permit.door
        }

        #expect(door == .unsequenced("manualLayoutEdit while postRestrictionRepair was writing"))
        #expect(repairs.ledger.causesWaiting(for: .manualLayoutEdit).isEmpty)
        #expect(repairs.ledger.isRunning(.postRestrictionRepair))
        repairs.leave(holder)
    }

    @Test("Entering marks the work as running and stamps what asked for it; leaving ends it")
    func enterAndLeaveKeepTheAccount() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.overflowRebalance, cause: .cachePublished)
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance) == [.cachePublished])

        let hold = try #require(await repairs.enter(.overflowRebalance))
        #expect(repairs.ledger.isRunning(.overflowRebalance))
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance).isEmpty)

        repairs.leave(hold)
        #expect(!repairs.ledger.isRunning(.overflowRebalance))
    }

    @Test("Work outside the lane is still counted as running, beside the pass that holds the lane")
    func unlanedWorkIsAccountedFor() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        repairs.begin(.deferredLayoutReconcile)
        #expect(repairs.ledger.isRunning(.deferredLayoutReconcile))
        #expect(repairs.ledger.isRunning(.postRestrictionRepair))

        repairs.end(.deferredLayoutReconcile)
        #expect(!repairs.ledger.isRunning(.deferredLayoutReconcile))
        #expect(repairs.ledger.isRunning(.postRestrictionRepair))
        repairs.leave(holder)
    }

    @Test("A pass cancelled while it waits for the lane is told not to write")
    func cancelledWhileQueued() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        let waiting = Task { @MainActor in await repairs.enter(.overflowRebalance) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        waiting.cancel()

        #expect(await waiting.value == nil)
        #expect(!repairs.ledger.isRunning(.overflowRebalance))
        repairs.leave(holder)
    }

    @Test("The ledger's summary lists what ran, what is running and what is waiting")
    func ledgerSummary() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.storeHygiene, cause: .cachePublished)
        let hold = try #require(await repairs.enter(.overflowRebalance))

        let summary = repairs.ledger.stateDescription
        #expect(summary.contains("overflowRebalance=1"))
        #expect(summary.contains("awake[overflowRebalance]"))
        #expect(summary.contains("waiting[storeHygiene]"))
        repairs.leave(hold)
    }

    @Test("A move that starts alone keeps a pass waiting until it ends")
    func moveHoldsAFreeLane() async throws {
        let repairs = RepairOrchestrator()
        let move = try #require(repairs.beginMove())
        var passRan = false

        let pass = Task { @MainActor in
            guard let hold = await repairs.enter(.structuralNormalization) else { return }
            passRan = true
            repairs.leave(hold)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!passRan)
        #expect(repairs.ledger.isRunning(.itemMove))

        repairs.endMove(move)
        await pass.value

        #expect(passRan)
        #expect(!repairs.ledger.isRunning(.itemMove))
    }

    @Test("A move asked for while a pass holds the lane runs without taking it")
    func moveInsideAPassLeavesTheLaneAlone() async throws {
        let repairs = RepairOrchestrator()
        let pass = try #require(await repairs.enter(.postRestrictionRepair))

        let move = repairs.beginMove()
        #expect(move == nil)
        #expect(repairs.ledger.isRunning(.itemMove))
        repairs.endMove(move)

        #expect(!repairs.ledger.isRunning(.itemMove))
        #expect(repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
            == .unsequenced("manualLayoutEdit while postRestrictionRepair was writing"))
        repairs.leave(pass)
    }

    /// One automatic pass that writes once through its permit.
    private func writingPass(_ repairs: RepairOrchestrator, _ work: RepairOrchestrator.Work = .postRestrictionRepair) async -> Bool {
        guard let hold = await repairs.enter(work) else { return false }
        StoreWriteAudit.note(StoreWritePermit(hold), write: "test")
        repairs.leave(hold)
        return true
    }

    @Test("Automatic passes that keep writing with nobody at the bar are paused")
    func writingLoopIsPaused() async {
        let repairs = RepairOrchestrator()
        for _ in 0 ... AutomaticWriteBudget.limit {
            #expect(await writingPass(repairs))
        }
        #expect(await repairs.enter(.structuralNormalization) == nil)
    }

    @Test("A pass that writes nothing never counts toward the pause")
    func silentPassesNeverPause() async throws {
        let repairs = RepairOrchestrator()
        for _ in 0 ..< 10 {
            let hold = try #require(await repairs.enter(.postRestrictionRepair))
            repairs.leave(hold)
        }
        #expect(await writingPass(repairs))
    }

    @Test("A user edit gets through a pause and lifts it")
    func userEditLiftsThePause() async throws {
        let repairs = RepairOrchestrator()
        for _ in 0 ... AutomaticWriteBudget.limit {
            _ = await writingPass(repairs)
        }
        let edit = try #require(await repairs.enterForUserEdit())
        repairs.leave(edit)
        #expect(await writingPass(repairs))
    }

    @Test("Showing a section counts as the user at the bar")
    func revealLiftsThePause() async {
        let repairs = RepairOrchestrator()
        for _ in 0 ... AutomaticWriteBudget.limit {
            _ = await writingPass(repairs)
        }
        repairs.request(.revealReconcile, cause: .sectionRevealed)
        #expect(await writingPass(repairs, .revealReconcile))
    }

    @Test("A reveal starting turns away an automatic pass waiting for the lane")
    func revealCallsOffAQueuedPass() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.arrivalOrderRestore))
        repairs.request(.overflowRebalance, cause: .cachePublished)
        let waiting = Task { @MainActor in await repairs.enter(.overflowRebalance) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        _ = repairs.writeNow(.preRevealOrder, cause: .revealStarting) { $0.door }

        #expect(await waiting.value == nil)
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance).isEmpty)
        repairs.leave(holder)
    }

    @Test("A pass asked for before a click does not start after it; one asked for after does")
    func clickCallsOffAPendingPass() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)

        repairs.interruptAutomaticWork(by: .userClickedItem)

        #expect(await repairs.enter(.postRestrictionRepair) == nil)
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)
        let hold = try #require(await repairs.enter(.postRestrictionRepair))
        repairs.leave(hold)
    }

    @Test("The normalization a ⌘-drag asked for keeps its turn when the user clicks")
    func dragNormalizationSurvivesAClick() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.structuralNormalization, cause: .userDragEnded)

        repairs.interruptAutomaticWork(by: .userClickedItem)

        let hold = try #require(await repairs.enter(.structuralNormalization))
        repairs.leave(hold)
    }

    @Test("A writing automatic pass is told to stop when a drag starts")
    func dragStopsAWritingPass() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)
        let hold = try #require(await repairs.enter(.postRestrictionRepair))
        #expect(!repairs.userWorkIsWaiting)

        repairs.interruptAutomaticWork(by: .userDragStarted)

        #expect(repairs.userWorkIsWaiting)
        repairs.leave(hold)
        #expect(!repairs.userWorkIsWaiting)
    }

    @Test("Work the user asked for is never turned away by user input")
    func userPriorityWorkIsNotCalledOff() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.revealReconcile, cause: .sectionRevealed)
        repairs.interruptAutomaticWork(by: .userClickedItem)
        repairs.request(.profileLayoutApply, cause: .profileApplied)
        repairs.interruptAutomaticWork(by: .userClickedItem)

        let hold = try #require(await repairs.enter(.profileLayoutApply, priority: .user))
        #expect(!repairs.userWorkIsWaiting)
        repairs.leave(hold)
    }

    @Test("User input lifts a pause")
    func inputLiftsThePause() async {
        let repairs = RepairOrchestrator()
        for _ in 0 ... AutomaticWriteBudget.limit {
            _ = await writingPass(repairs)
        }
        repairs.interruptAutomaticWork(by: .userDragStarted)
        #expect(await writingPass(repairs))
    }

    @Test("Only the causes that start something the user does call off automatic work")
    func interruptingCauses() {
        let interrupting = Set([RepairOrchestrator.Cause.revealStarting, .userDragStarted, .userClickedItem])
        for cause in [RepairOrchestrator.Cause.revealStarting, .userDragStarted, .userClickedItem, .userDragEnded, .sectionRevealed, .restrictionChanged, .settled] {
            #expect(cause.interruptsAutomaticWork == interrupting.contains(cause))
        }
        let allAreUserActions = interrupting.allSatisfy(\.isUserAction)
        #expect(allAreUserActions)
    }

    /// Whether each cause is a user action, interrupts automatic work, and changes the layout by the user, in that order.
    private static let traitTable: [RepairOrchestrator.Cause: (user: Bool, interrupts: Bool, layout: Bool)] = [
        .userDragEnded: (true, false, true),
        .moveFulfilled: (false, false, false),
        .structuralDriftObserved: (false, false, false),
        .revealHideTransition: (false, false, false),
        .settled: (false, false, false),
        .restrictionChanged: (false, false, false),
        .cachePublished: (false, false, false),
        .nativeOverflowChanged: (false, false, false),
        .arrivalDisturbedOrder: (false, false, false),
        .layoutApplyBlocked: (false, false, false),
        .rearmed: (false, false, false),
        .userEdit: (true, false, true),
        .profileApplied: (false, false, false),
        .settingChanged: (false, false, false),
        .sectionRevealed: (true, false, false),
        .revealStarting: (true, true, false),
        .userDragStarted: (true, true, false),
        .userClickedItem: (true, true, false),
        .policyReveal: (false, false, false),
    ]

    @Test("Every cause keeps its place on the user or automatic side, and a policy reveal is automatic")
    func everyCauseIsPinned() {
        #expect(Set(Self.traitTable.keys) == Set(RepairOrchestrator.Cause.allCases))
        for (cause, traits) in Self.traitTable {
            #expect(cause.isUserAction == traits.user, "\(cause.rawValue)")
            #expect(cause.interruptsAutomaticWork == traits.interrupts, "\(cause.rawValue)")
            #expect(cause.isLayoutChangeByUser == traits.layout, "\(cause.rawValue)")
        }
    }

    @Test(
        "A reveal Thaw makes by itself leaves a queued automatic pass its turn; a user's reveal still calls it off",
        arguments: [(RepairOrchestrator.Cause.policyReveal, true), (.revealStarting, false)]
    )
    func preRevealWriteAndAQueuedPass(cause: RepairOrchestrator.Cause, passRuns: Bool) async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.arrivalOrderRestore))
        repairs.request(.overflowRebalance, cause: .cachePublished)
        let waiting = Task { @MainActor in await repairs.enter(.overflowRebalance) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        _ = repairs.writeNow(.preRevealOrder, cause: cause) { $0.door }
        repairs.leave(holder)

        let hold = await waiting.value
        #expect((hold != nil) == passRuns)
        if let hold {
            repairs.leave(hold)
        }
    }

    @Test(
        "A policy reveal's restore request leaves a planned pass alone; a user's reveal calls it off",
        arguments: [(RepairOrchestrator.Cause.policyReveal, true), (.revealStarting, false)]
    )
    func revealRequestAndAPlannedPass(cause: RepairOrchestrator.Cause, passRuns: Bool) async {
        let repairs = RepairOrchestrator()
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)

        repairs.request(.revealReconcile, cause: cause)

        let hold = await repairs.enter(.postRestrictionRepair)
        #expect((hold != nil) == passRuns)
        if let hold {
            repairs.leave(hold)
        }
    }

    @Test("A policy reveal leaves the loop pause in place")
    func policyRevealKeepsThePause() async {
        let repairs = RepairOrchestrator()
        for _ in 0 ... AutomaticWriteBudget.limit {
            _ = await writingPass(repairs)
        }

        _ = repairs.writeNow(.preRevealOrder, cause: .policyReveal) { $0.door }
        repairs.request(.revealReconcile, cause: .policyReveal)

        #expect(await repairs.enter(.structuralNormalization) == nil)
    }

    @Test("The restore a policy reveal asked for keeps its turn when the user clicks")
    func policyRevealRestoreSurvivesAClick() {
        let repairs = RepairOrchestrator()
        repairs.request(.revealReconcile, cause: .policyReveal)

        repairs.interruptAutomaticWork(by: .userClickedItem)

        #expect(repairs.ledger.causesWaiting(for: .revealReconcile) == [.policyReveal])
    }
}
