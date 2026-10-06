//
//  RepairLaneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Automatic repair passes follow one another")
struct RepairLaneTests {
    /// Yields until the lane has this many passes queued.
    private func waitForQueue(_ count: Int, in lane: RepairLane) async {
        for _ in 0 ..< 1000 where lane.queued.count != count {
            await Task.yield()
        }
    }

    @Test("A free lane admits at once; later passes run in the order they asked")
    func passesRunInOrder() async throws {
        let lane = RepairLane()
        var order: [RepairOrchestrator.Work] = []

        let first = try #require(await lane.enter(.postRestrictionRepair))
        let second = Task { @MainActor in
            guard let hold = await lane.enter(.structuralNormalization) else { return }
            order.append(hold.work)
            lane.leave(hold)
        }
        await waitForQueue(1, in: lane)
        let third = Task { @MainActor in
            guard let hold = await lane.enter(.overflowRebalance) else { return }
            order.append(hold.work)
            lane.leave(hold)
        }
        await waitForQueue(2, in: lane)

        #expect(lane.current == .postRestrictionRepair)
        #expect(lane.queued == [.structuralNormalization, .overflowRebalance])
        #expect(order.isEmpty)

        lane.leave(first)
        await second.value
        await third.value

        #expect(order == [.structuralNormalization, .overflowRebalance])
        #expect(lane.current == nil)
    }

    @Test("User work goes ahead of waiting automatic passes, behind earlier user work, and never interrupts the holder")
    func userWorkJumpsTheQueue() async throws {
        let lane = RepairLane()
        var order: [RepairOrchestrator.Work] = []
        func queue(_ work: RepairOrchestrator.Work, _ priority: RepairLane.Priority) -> Task<Void, Never> {
            Task { @MainActor in
                guard let hold = await lane.enter(work, priority: priority) else { return }
                order.append(hold.work)
                lane.leave(hold)
            }
        }

        let holder = try #require(await lane.enter(.postRestrictionRepair))
        let automatic = queue(.structuralNormalization, .automatic)
        await waitForQueue(1, in: lane)
        let firstUser = queue(.authoredOrderApply, .user)
        await waitForQueue(2, in: lane)
        let laterAutomatic = queue(.overflowRebalance, .automatic)
        await waitForQueue(3, in: lane)
        let secondUser = queue(.storeHygiene, .user)
        await waitForQueue(4, in: lane)

        #expect(lane.current == .postRestrictionRepair)
        #expect(lane.queued == [.authoredOrderApply, .storeHygiene, .structuralNormalization, .overflowRebalance])

        lane.leave(holder)
        for task in [automatic, firstUser, laterAutomatic, secondUser] {
            await task.value
        }
        #expect(order == [.authoredOrderApply, .storeHygiene, .structuralNormalization, .overflowRebalance])
    }

    @Test("A synchronous writer takes a free lane and is refused a held one")
    func enterIfFree() throws {
        let lane = RepairLane()

        let first = try #require(lane.enterIfFree(.preRevealOrder))
        #expect(lane.current == .preRevealOrder)
        #expect(lane.enterIfFree(.manualLayoutEdit) == nil)

        lane.leave(first)
        let second = try #require(lane.enterIfFree(.manualLayoutEdit))
        lane.leave(second)
        #expect(lane.current == nil)
    }

    @Test("A pass cancelled while it queued drops out of line and never runs")
    func cancelledWaiterDropsOut() async throws {
        let lane = RepairLane()
        let first = try #require(await lane.enter(.postRestrictionRepair))

        let superseded = Task { @MainActor in
            await lane.enter(.structuralNormalization)
        }
        await waitForQueue(1, in: lane)
        let next = Task { @MainActor in
            await lane.enter(.arrivalOrderRestore)
        }
        await waitForQueue(2, in: lane)

        superseded.cancel()
        #expect(await superseded.value == nil)
        #expect(lane.queued == [.arrivalOrderRestore])

        lane.leave(first)
        let hold = try #require(await next.value)
        #expect(lane.current == .arrivalOrderRestore)
        lane.leave(hold)
        #expect(lane.current == nil)
    }

    @Test("An already cancelled task is not admitted")
    func cancelledTaskIsNotAdmitted() async {
        let lane = RepairLane()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await lane.enter(.overflowRebalance)
        }
        #expect(await task.value == nil)
        #expect(lane.current == nil)
    }

    @Test("A pass that never returns loses the lane, and its late leave changes nothing")
    func staleHolderIsTakenOver() async throws {
        let lane = RepairLane()
        let start = ContinuousClock.now

        let stuck = try #require(await lane.enter(.postRestrictionRepair, at: start))
        let taker = try #require(
            await lane.enter(.structuralNormalization, at: start + RepairLane.staleAfter + .seconds(1))
        )

        #expect(lane.takeovers == 1)
        #expect(lane.current == .structuralNormalization)

        lane.leave(stuck)
        #expect(lane.current == .structuralNormalization)

        lane.leave(taker)
        #expect(lane.current == nil)
    }

    @Test("A holder within its time is not taken over")
    func freshHolderKeepsTheLane() async throws {
        let lane = RepairLane()
        let start = ContinuousClock.now
        let first = try #require(await lane.enter(.postRestrictionRepair, at: start))

        let second = Task { @MainActor in
            await lane.enter(.overflowRebalance, at: start + .seconds(5))
        }
        await waitForQueue(1, in: lane)

        #expect(lane.takeovers == 0)
        #expect(lane.current == .postRestrictionRepair)

        lane.leave(first)
        let hold = try #require(await second.value)
        lane.leave(hold)
    }
}
