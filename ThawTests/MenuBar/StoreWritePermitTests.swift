//
//  StoreWritePermitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A position-table write names the door it came through")
struct StoreWritePermitTests {
    @Test("A pass the lane admitted writes under that pass's name")
    func repairLaneDoor() async throws {
        let lane = RepairLane()
        let hold = try #require(await lane.enter(.structuralNormalization))
        defer { lane.leave(hold) }

        let door = StoreWritePermit(hold).door
        #expect(door == .repairLane(.structuralNormalization))
        #expect(door.description == "repairLane(structuralNormalization)")
    }

    @Test("The move permit hands out a permit only while it is held")
    func moveMutationDoor() async throws {
        let semaphore = SimpleSemaphore(value: 1)
        var order: [String] = []

        let door = try await semaphore.withStoreWritePermit { permit in
            order.append("first in")
            let door = permit.door
            let second = Task { @MainActor in
                try await semaphore.withStoreWritePermit { _ in order.append("second in") }
            }
            // The second caller cannot be let in while this one holds the permit.
            for _ in 0 ..< 50 {
                await Task.yield()
            }
            order.append("first out")
            _ = second
            return door
        }

        #expect(door == .moveMutation)
        try await semaphore.withStoreWritePermit { _ in }
        #expect(order == ["first in", "first out", "second in"])
    }

    @Test("A writer through neither door is named, and counted apart")
    func unsequencedIsNamedAndCounted() {
        let store = PermittedPositionStore(wrapping: RecordingStore())
        let before = StoreWriteAudit.unsequenced["unsequenced(test path)", default: 0]

        store.writePositions(["a": 1], permit: .unsequenced("test path"))
        store.writePositions(["a": 2], permit: .unsequenced("test path"))

        #expect(StoreWriteAudit.unsequenced["unsequenced(test path)"] == before + 2)
    }

    @Test("A permitted write reaches the store underneath; reads need no permit")
    func writesPassThrough() async throws {
        let base = RecordingStore()
        let store = PermittedPositionStore(wrapping: base)
        let lane = RepairLane()
        let hold = try #require(await lane.enter(.overflowRebalance))
        defer { lane.leave(hold) }
        let before = StoreWriteAudit.counts["repairLane(overflowRebalance)", default: 0]

        store.writePositions(["status:App::Item-0": 40], permit: StoreWritePermit(hold))

        #expect(base.positions == ["status:App::Item-0": 40])
        #expect(store.readPositions() == ["status:App::Item-0": 40])
        #expect(StoreWriteAudit.counts["repairLane(overflowRebalance)"] == before + 1)
        #expect(!store.refusesOrdering)
    }

    @Test("Manual arrangement still refuses ordering underneath the permit")
    func manualRefusalStillApplies() {
        let store = PermittedPositionStore(wrapping: ReadOnlyPositionStore(wrapping: RecordingStore()))
        #expect(store.refusesOrdering)
        let changed = store.respaceOrder(
            desiredOrder: ["a", "b"],
            liveItems: [],
            experimentalSystemItemHiding: false,
            permit: .unsequenced("test path")
        )
        #expect(changed.isEmpty)
    }
}

/// A dictionary standing in for the live table.
@MainActor
private final class RecordingStore: MenuBarPositionStoring {
    private(set) var positions: [String: Int] = [:]

    func currentPositions() -> [String: Int] {
        positions
    }

    func readPositions() -> [String: Int] {
        positions
    }

    func writePositions(_ positions: [String: Int]) {
        self.positions = positions
    }

    func resolveKey(
        for _: MenuBarItem,
        existingKeys _: [String],
        positions _: [String: Int],
        liveItems _: [MenuBarItem]
    ) -> String? {
        nil
    }

    func parseStatusKey(_: String) -> PositionStatusKey? {
        nil
    }

    func isParkedWeight(_: Int) -> Bool {
        false
    }

    @discardableResult
    func move(
        item _: MenuBarItem,
        to _: MoveDestination,
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> Bool {
        true
    }

    func applyOrder(
        desiredOrder: [String],
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> [String] {
        desiredOrder
    }

    func respaceOrder(
        desiredOrder: [String],
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> [String] {
        desiredOrder
    }

    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func applyControlItemOrder(
        desiredOrder _: [MenuBarItem],
        opaqueVisibleKeys _: [String],
        liveItems _: [MenuBarItem]
    ) -> [String] {
        []
    }

    func isProvenAbsent(_: String) -> Bool {
        false
    }

    @discardableResult
    func recordAbsenceEvidence(seen _: Set<String>, blank _: Set<String>) -> Set<String> {
        []
    }

    func resetAbsenceEvidence() {}
}
