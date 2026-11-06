//
//  InventoryWalkScenarioTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// The plan, the ledger and the scan state together, over a run of reads.
@MainActor
struct InventoryWalkScenarioTests {
    private struct Bar {
        var state = MenuBarScanState<String>()
        let ledger = FullWalkLedger()
        /// What each app answers when asked. An app missing here does not answer in time.
        var answers: [Int32: [String]]

        /// One read: plan it, ask the chosen apps, and note a finished full walk.
        @discardableResult
        mutating func read(drawn: Set<Int32>?, at now: ContinuousClock.Instant) -> (scope: MenuBarScanScope, asked: Set<Int32>) {
            let running = Array(answers.keys).sorted()
            let plan = InventoryWalkPlan.make(requested: [], drawnOwners: drawn, lastFullWalk: ledger.lastFullWalk, now: now)
            let pass = state.begin(owners: running, priorityOwners: plan.priorityOwners, scope: plan.scope, now: now)
            for owner in pass.owners {
                state.didAttempt(owner: owner, generation: pass.generation)
                if let answer = answers[owner] {
                    state.record(answer, owner: owner, generation: pass.generation, at: now)
                }
            }
            if plan.scope == .discovery, state.hasFreshKnownInventory(generation: pass.generation) {
                ledger.noteFullWalk(at: now)
            }
            return (plan.scope, Set(pass.owners))
        }

        var items: [String] { state.observations.sorted() }
    }

    private let start = ContinuousClock.now

    /// Apps 1 and 2 have an item each; 3 to 6 have none.
    private func bar() -> Bar {
        Bar(answers: [1: ["a"], 2: ["b"], 3: [], 4: [], 5: [], 6: []])
    }

    @Test
    func `the first read asks every app, and the next asks only the two with items`() {
        var bar = bar()
        let first = bar.read(drawn: [1], at: start)
        #expect(first.scope == .discovery)
        #expect(first.asked == [1, 2, 3, 4, 5, 6])

        let second = bar.read(drawn: [1], at: start + .seconds(3))
        #expect(second.scope == .settledOwners)
        #expect(second.asked == [1, 2])
        #expect(bar.items == ["a", "b"])
    }

    @Test
    func `a hidden item is still read, though it is not drawn`() {
        var bar = bar()
        bar.read(drawn: [1], at: start)
        bar.answers[2] = ["b-moved"]
        bar.read(drawn: [1], at: start + .seconds(3))
        #expect(bar.items == ["a", "b-moved"])
    }

    @Test
    func `an app that puts its first item on the bar is picked up on the next read`() {
        var bar = bar()
        bar.read(drawn: [1], at: start)
        bar.answers[5] = ["new"]
        let read = bar.read(drawn: [1, 5], at: start + .seconds(3))
        #expect(read.asked == [1, 2, 5])
        #expect(bar.items == ["a", "b", "new"])
    }

    @Test
    func `an item that appears hidden is missed until the next full walk finds it`() {
        var bar = bar()
        bar.read(drawn: [1], at: start)
        bar.answers[5] = ["hidden-new"]
        bar.read(drawn: [1], at: start + .seconds(3))
        #expect(bar.items == ["a", "b"])

        let later = bar.read(drawn: [1], at: start + InventoryWalkPlan.fullWalkInterval)
        #expect(later.scope == .discovery)
        #expect(bar.items == ["a", "b", "hidden-new"])
    }

    @Test
    func `a newly launched app is asked once without waiting for a full walk`() {
        var bar = bar()
        bar.read(drawn: [1], at: start)
        bar.answers[7] = ["launched-hidden"]
        let read = bar.read(drawn: [1], at: start + .seconds(3))
        #expect(read.asked == [1, 2, 7])
        #expect(bar.items == ["a", "b", "launched-hidden"])
    }

    @Test
    func `a read caught mid-change asks every app`() {
        var bar = bar()
        bar.read(drawn: [1], at: start)
        let read = bar.read(drawn: nil, at: start + .seconds(3))
        #expect(read.scope == .discovery)
        #expect(read.asked == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func `full walks keep running until one hears from every app`() {
        var bar = bar()
        // App 6 is running and never answers. It is asked through the state directly, since read() only knows apps with answers.
        let pass = bar.state.begin(owners: [1, 2, 3, 6], priorityOwners: [], scope: .discovery, now: start)
        for owner in pass.owners where owner != 6 {
            bar.state.didAttempt(owner: owner, generation: pass.generation)
            bar.state.record(bar.answers[owner] ?? [], owner: owner, generation: pass.generation, at: start)
        }
        bar.state.didAttempt(owner: 6, generation: pass.generation)

        #expect(!bar.state.hasFreshKnownInventory(generation: pass.generation))
        let next = InventoryWalkPlan.make(requested: [], drawnOwners: [1], lastFullWalk: bar.ledger.lastFullWalk, now: start + .seconds(3))
        #expect(next.scope == .discovery)
    }

    @Test
    func `an app that quits takes its item with it on the next read`() {
        var bar = bar()
        bar.read(drawn: [1], at: start)
        bar.answers.removeValue(forKey: 2)
        bar.read(drawn: [1], at: start + .seconds(3))
        #expect(bar.items == ["a"])
    }
}
