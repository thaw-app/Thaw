//
//  MenuBarScanStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

extension MenuBarScanState where Observation == String {
    /// Asks one owner in `pass` and records its answer.
    mutating func answer(_ owner: Int32, _ items: [String], in pass: Pass, at instant: ContinuousClock.Instant = .now) {
        didAttempt(owner: owner, generation: pass.generation)
        record(items, owner: owner, generation: pass.generation, at: instant)
    }

    /// Asks every owner in `pass`; each answers `items(owner)`, by default one item named for it.
    mutating func answerAll(
        _ pass: Pass,
        at instant: ContinuousClock.Instant = .now,
        items: (Int32) -> [String] = { ["item-\($0)"] }
    ) {
        for owner in pass.owners {
            answer(owner, items(owner), in: pass, at: instant)
        }
    }

    /// Discovery has seen owners 1 to 4; 1 and 2 own items, 3 and 4 answered empty.
    static func discovered(at now: ContinuousClock.Instant) -> Self {
        var state = Self()
        state.answerAll(state.begin(owners: [1, 2, 3, 4], priorityOwners: [], now: now), at: now) {
            $0 <= 2 ? ["item-\($0)"] : []
        }
        return state
    }
}

@Suite("Budgeted menu bar discovery")
struct MenuBarScanStateTests {
    @Test("Repeated short scans reach every owner and always visit controls first")
    func truncatedScansMakeProgress() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 199)
        var visited = Set<Int32>()
        for _ in 0 ..< 3 {
            let pass = state.begin(owners: owners, priorityOwners: [198, 199])
            #expect(Array(pass.owners.prefix(2)) == [198, 199])
            for owner in pass.owners.prefix(100) {
                state.answer(owner, ["item-\(owner)"], in: pass)
                visited.insert(owner)
            }
        }
        #expect(visited == Set(owners))
        #expect(state.observations.count == 199)
    }

    @Test("A process that launched since the last scan is asked before the rotation")
    func newOwnerIsNotLeftBehindATruncatedScan() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 100)
        state.answerAll(state.begin(owners: owners, priorityOwners: [100])) { _ in [] }
        let second = state.begin(owners: owners + [500], priorityOwners: [100])
        #expect(Array(second.owners.prefix(2)) == [100, 500])
    }

    /// 2026-11-06: four processes launched after the last full walk made every capture read fall
    /// back to a two-second walk of every app, though all 17 item owners had answered.
    @Test("An owner never read doesn't hold up the known owners, but a stale item owner does")
    func neverReadOwnersDontBlockKnownOwners() {
        var state = MenuBarScanState<String>()
        state.answerAll(state.begin(owners: [1, 2], priorityOwners: [])) { $0 == 1 ? ["item"] : [] }

        let targeted = state.begin(owners: [1, 2, 3], priorityOwners: [1], scope: .requestedOwners)
        state.answer(1, ["item"], in: targeted)

        // The strict check still waits for 3.
        #expect(!state.hasFreshKnownInventory(generation: targeted.generation))
        #expect(state.hasFreshItemOwners(generation: targeted.generation))

        // Owner 1 has items and isn't read again.
        let stale = state.begin(owners: [1, 2, 3], priorityOwners: [2], scope: .requestedOwners)
        state.answer(2, [], in: stale)
        #expect(!state.hasFreshItemOwners(generation: stale.generation))
        #expect(state.hasFreshItemOwners(generation: stale.generation, excusing: [1]))
    }

    @Test("Background-only owners are asked after every other owner, but still asked")
    func backgroundOwnersGoLast() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [5], deferredOwners: [2, 5])
        #expect(pass.owners == [5, 1, 3, 4, 2])
    }

    @Test("A walk that ran out of time before the background-only owners is still complete")
    func excusedBackgroundOwnersDoNotBlockCompleteness() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2], priorityOwners: [], deferredOwners: [2])
        state.answer(1, ["item"], in: pass)
        #expect(!state.isComplete(generation: pass.generation))
        #expect(!state.hasFreshKnownInventory(generation: pass.generation))
        // Owner 2 can't own an item, so leaving it unread proves nothing was missed.
        #expect(state.isComplete(pass, excusing: [2]))
        #expect(state.hasFreshKnownInventory(generation: pass.generation, excusing: [2]))
    }

    @Test("A background-only owner is excused only while Thaw holds no items for it")
    func deferredOwnerWithItemsIsNotExcused() {
        var state = MenuBarScanState<String>()
        // Owner 2 once showed an item; owner 3 answered empty; owner 4 was never read.
        let first = state.begin(owners: [1, 2, 3, 4], priorityOwners: [])
        state.answer(1, ["one"], in: first)
        state.answer(2, ["two"], in: first)
        state.answer(3, [], in: first)

        // A later walk reads owner 1 and runs out of time before the deferred owners.
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], deferredOwners: [2, 3, 4])
        state.answer(1, ["one"], in: pass)

        let excused = state.excusableDeferredOwners(of: pass)
        #expect(excused == [3, 4])
        // Owner 2's item wasn't read again, so its geometry is stale and the inventory isn't fresh.
        #expect(!state.hasFreshKnownInventory(generation: pass.generation, excusing: excused))
        #expect(!state.isComplete(pass, excusing: excused))

        // Once owner 2 answers empty it is excused like the others.
        let next = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], deferredOwners: [2, 3, 4])
        state.answer(1, ["one"], in: next)
        state.answer(2, [], in: next)
        let nextExcused = state.excusableDeferredOwners(of: next)
        #expect(nextExcused == [2, 3, 4])
        #expect(state.hasFreshKnownInventory(generation: next.generation, excusing: nextExcused))
    }

    @Test("A pass that skipped a hung owner with known items is steady but not fresh")
    func skippedKnownOwnerIsSteady() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        state.answerAll(first)
        #expect(state.coverage(of: first) == InventoryCoverage(isFresh: true, isSteady: true))

        // Owner 2 hangs: the next walk skips it and reads owner 1.
        let pass = state.begin(owners: [1, 2], priorityOwners: [])
        state.answer(1, ["item-1"], in: pass)

        #expect(state.coverage(of: pass, skipped: [2]) == InventoryCoverage(isFresh: false, isSteady: true))
        #expect(state.observations.sorted() == ["item-1", "item-2"])
        // Not named as skipped, the same gap is a read that didn't get to owner 2.
        #expect(state.coverage(of: pass) == .none)
    }

    @Test("A skipped owner that was never read is not excused, and neither is a walk cut short")
    func unreadOwnersAreNotSteady() {
        var state = MenuBarScanState<String>()
        // A launch walk: owner 1 answers, owner 2 is skipped as slow, and time runs out before owner 3.
        let launch = state.begin(owners: [1, 2, 3], priorityOwners: [])
        state.answer(1, ["item-1"], in: launch)
        #expect(state.coverage(of: launch, skipped: [2]) == .none)

        // Later every owner has answered once, then a walk reads owner 1 and is cut short before 2 and 3.
        state.answer(2, ["item-2"], in: launch)
        state.answer(3, ["item-3"], in: launch)
        let truncated = state.begin(owners: [1, 2, 3], priorityOwners: [])
        state.answer(1, ["item-1"], in: truncated)
        // Owner 3 was not skipped, only not reached.
        #expect(state.coverage(of: truncated, skipped: [2]) == .none)
    }

    @Test("An unvisited owner survives, but a successful empty answer removes its items")
    func absenceRequiresAnObservation() {
        var state = MenuBarScanState<String>()
        state.answerAll(state.begin(owners: [1, 2], priorityOwners: []))
        let second = state.begin(owners: [1, 2], priorityOwners: [])
        state.answer(1, [], in: second)
        #expect(state.observations == ["item-2"])
        #expect(state.freshObservations(generation: second.generation).isEmpty)
        #expect(!state.isComplete(generation: second.generation))
        _ = state.begin(owners: [1], priorityOwners: [])
        #expect(state.observations.isEmpty)
    }

    @Test("Reconciliation needs discovery coverage and fresh geometry for every known item")
    func reconciliationDoesNotWaitForEmptyOwnersEveryPass() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        state.answer(1, ["control"], in: first)
        #expect(!state.hasFreshKnownInventory(generation: first.generation))
        state.answer(2, [], in: first)

        let second = state.begin(owners: [1, 2], priorityOwners: [])
        #expect(!state.hasFreshKnownInventory(generation: second.generation))
        state.answer(1, ["control moved"], in: second)
        #expect(!state.isComplete(generation: second.generation))
        #expect(state.hasFreshKnownInventory(generation: second.generation))

        let third = state.begin(owners: [1, 2, 3], priorityOwners: [])
        #expect(!state.hasFreshKnownInventory(generation: third.generation))
    }

    @Test("A late pre-move answer cannot overwrite a newer observation")
    func staleAnswersAreRejected() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: first.generation)
        let second = state.begin(owners: [1], priorityOwners: [])
        state.answer(1, ["new position"], in: second)
        state.record(["old position"], owner: 1, generation: first.generation)
        #expect(state.observations == ["new position"])
        #expect(state.isComplete(generation: second.generation))
    }
}

@Suite("Known-owner reads for moves")
struct MenuBarScanKnownOwnersTests {
    @Test("Cold and newly running owners are discovered, terminated owners are removed")
    func processChangesUpdateCoverage() {
        var state = MenuBarScanState<String>()
        let cold = state.begin(owners: [1, 2], priorityOwners: [], scope: .knownOwners)
        #expect(Set(cold.owners) == [1, 2])
        state.answerAll(cold)
        let changed = state.begin(owners: [2, 3], priorityOwners: [1], scope: .knownOwners)
        #expect(Set(changed.owners) == [2, 3])
        #expect(state.observations == ["item-2"])
        state.record(["departed late answer"], owner: 1, generation: cold.generation)
        #expect(state.observations == ["item-2"])
    }

    @Test("A missing neighbour or late pre-write answer cannot complete move geometry")
    func incompleteGeometryCannotVerify() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        state.answerAll(first) { ["old-\($0)"] }
        let move = state.begin(owners: [1, 2], priorityOwners: [1], scope: .knownOwners)
        for owner in move.owners {
            state.didAttempt(owner: owner, generation: move.generation)
        }
        state.record(["source"], owner: 1, generation: move.generation)
        state.record(["stale neighbour"], owner: 2, generation: first.generation)
        #expect(!state.isComplete(move))
        #expect(!state.hasFreshKnownInventory(generation: move.generation))
        #expect(state.freshObservations(generation: move.generation) == ["source"])
        state.record(["fresh neighbour"], owner: 2, generation: move.generation)
        #expect(state.isComplete(move))
        #expect(state.freshObservations(generation: move.generation) == ["source", "fresh neighbour"])
    }

    @Test("An excused slow neighbour completes move geometry without contributing stale items")
    func excusedNeighbourCompletesGeometry() {
        var state = MenuBarScanState<String>()
        state.answerAll(state.begin(owners: [1, 2], priorityOwners: [])) { ["old-\($0)"] }
        let move = state.begin(owners: [1, 2], priorityOwners: [1], scope: .knownOwners)
        state.answer(1, ["source"], in: move)
        #expect(!state.isComplete(move))
        #expect(state.isComplete(move, excusing: [2]))
        #expect(state.hasFreshKnownInventory(generation: move.generation, excusing: [2]))
        #expect(!state.isComplete(move, excusing: [3]))
        #expect(state.freshObservations(generation: move.generation) == ["source"])
    }

    @Test("Previously empty owners are rediscovered after five seconds")
    func emptyOwnerKnowledgeExpires() {
        var state = MenuBarScanState<String>()
        let start = ContinuousClock.now
        state.answerAll(state.begin(owners: [1, 2], priorityOwners: [], now: start), at: start) {
            $0 == 1 ? ["item"] : []
        }
        let recent = state.begin(owners: [1, 2], priorityOwners: [], scope: .knownOwners, now: start + .seconds(1))
        #expect(recent.owners == [1])
        let expired = state.begin(owners: [1, 2], priorityOwners: [], scope: .knownOwners, now: start + .seconds(5))
        #expect(Set(expired.owners) == [1, 2])
    }

    @Test("A requested empty owner must answer again before a move can be verified")
    func priorityOwnerCannotUseAnOldEmptyAnswer() {
        var state = MenuBarScanState<String>()
        state.answerAll(state.begin(owners: [1, 2], priorityOwners: [])) { $0 == 1 ? ["source"] : [] }
        let move = state.begin(owners: [1, 2], priorityOwners: [2], scope: .knownOwners)
        for owner in move.owners {
            state.didAttempt(owner: owner, generation: move.generation)
        }
        state.record(["fresh source"], owner: 1, generation: move.generation)
        #expect(state.hasFreshKnownInventory(generation: move.generation))
        #expect(!state.isComplete(move))
        state.record([], owner: 2, generation: move.generation)
        #expect(state.isComplete(move))
    }

    @Test("An unresolved probe invalidates an older empty answer")
    func timedOutEmptyOwnerIsRetried() {
        var state = MenuBarScanState<String>()
        state.answer(1, [], in: state.begin(owners: [1], priorityOwners: []))
        let pending = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: pending.generation)
        let move = state.begin(owners: [1], priorityOwners: [], scope: .knownOwners)
        #expect(move.owners == [1])
    }

    @Test("Move scans retain neighbour coverage without probing 122 empty applications")
    func knownOwnersIncludeNeighbours() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 126)
        state.answerAll(state.begin(owners: owners, priorityOwners: [])) { $0 <= 3 ? ["item-\($0)"] : [] }
        let move = state.begin(owners: owners, priorityOwners: [1, 2, 126], scope: .knownOwners)
        #expect(Set(move.owners) == [1, 2, 3, 126])
        state.answerAll(move) { ["fresh-\($0)"] }
        #expect(state.hasFreshKnownInventory(generation: move.generation))
        #expect(state.freshObservations(generation: move.generation).contains("fresh-3"))
    }

    @Test("The wider known-owners read probes empty apps again after five seconds")
    func knownOwnersReprobesExpiredEmpties() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let move = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .knownOwners, now: start + .seconds(60))
        #expect(Set(move.owners) == [1, 2, 3, 4])
    }
}
