//
//  ReadOnlyPositionStoreForwardingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("The read-only store reads through and refuses every ordering write")
struct ReadOnlyPositionStoreForwardingTests {
    private typealias Spy = PositionStoreSpy

    private func item(_ name: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(name)"), title: name, instanceIndex: 0),
            windowID: 1, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24), title: name, isOnScreen: true
        )
    }

    @Test("Reads, the raw write and the absence ledger reach the live store with its answers")
    func readsGoThrough() {
        let spy = Spy()
        let store = ReadOnlyPositionStore(wrapping: spy)

        #expect(store.currentPositions() == ["current": 1])
        #expect(store.readPositions() == ["read": 2])
        #expect(store.positionsDomainIsAccessible())
        #expect(store.resolveKey(for: item("A"), existingKeys: [], positions: [:], liveItems: []) == "status:A")
        #expect(store.parseStatusKey("k")?.identifier == "k")
        #expect(store.isParkedWeight(5000))
        #expect(!store.isParkedWeight(10))
        #expect(store.isProvenAbsent("gone"))
        #expect(store.recordAbsenceEvidence(seen: ["s"], blank: []) == ["s"])
        store.resetAbsenceEvidence()
        store.writePositions(["a": 1, "b": 2])

        #expect(spy.calls == [
            "currentPositions", "readPositions", "positionsDomainIsAccessible", "resolveKey", "parseStatusKey k",
            "isParkedWeight", "isParkedWeight", "isProvenAbsent", "recordAbsenceEvidence", "resetAbsenceEvidence",
            "writePositions 2",
        ])
    }

    @Test("Moves and ordering writes report nothing done and never reach the live store")
    func orderingIsRefused() {
        let spy = Spy()
        let store = ReadOnlyPositionStore(wrapping: spy)
        let a = item("A"), b = item("B")

        #expect(!store.move(item: a, to: .leftOfItem(b), liveItems: [a, b], experimentalSystemItemHiding: false))
        #expect(store.applyOrder(desiredOrder: ["a", "b"], liveItems: [a, b], experimentalSystemItemHiding: false).isEmpty)
        #expect(store.respaceOrder(desiredOrder: ["a", "b"], liveItems: [a, b], experimentalSystemItemHiding: true).isEmpty)
        #expect(store.breakTiedSiblingWeights(liveItems: [a, b]).isEmpty)
        #expect(spy.calls.isEmpty, "a refused write reached the live store: \(spy.calls)")
    }

    @Test("Seating controls with fewer than two items or an empty table writes nothing")
    func seatingNeedsAnOrderAndATable() {
        let spy = Spy()
        let store = ReadOnlyPositionStore(wrapping: spy)

        #expect(store.applyControlItemOrder(desiredOrder: [item("A")], opaqueVisibleKeys: [], liveItems: []).isEmpty)
        #expect(spy.calls.isEmpty)
    }

    @Test("The permitted store knows a read-only store refuses ordering")
    func permittedStoreSeesTheRefusal() {
        #expect(PermittedPositionStore(wrapping: ReadOnlyPositionStore(wrapping: Spy())).refusesOrdering)
    }
}

@MainActor
@Suite("A stored weights table is read once from the store")
struct StoredWeightsTableTests {
    @Test("An accessible store is read for its current positions")
    func accessibleStoreIsRead() {
        let spy = PositionStoreSpy()
        let table = StoredWeights.Table.read(from: PermittedPositionStore(wrapping: spy))
        #expect(StoredWeights(among: [], table: table).isAvailable)
        #expect(spy.calls == ["positionsDomainIsAccessible", "currentPositions"])
    }

    @Test("An inaccessible store is not read and the table is unavailable")
    func inaccessibleStoreIsNotRead() {
        let spy = PositionStoreSpy()
        spy.isAccessible = false
        let table = StoredWeights.Table.read(from: PermittedPositionStore(wrapping: spy))
        #expect(!StoredWeights(among: [], table: table).isAvailable)
        #expect(spy.calls == ["positionsDomainIsAccessible"])
    }
}

/// Records each call by name and answers with values a test can tell apart.
@MainActor
private final class PositionStoreSpy: MenuBarPositionStoring {
    var calls: [String] = []
    var isAccessible = true

    func currentPositions() -> [String: Int] {
        calls.append("currentPositions"); return ["current": 1]
    }

    func readPositions() -> [String: Int] {
        calls.append("readPositions"); return ["read": 2]
    }

    func positionsDomainIsAccessible() -> Bool {
        calls.append("positionsDomainIsAccessible"); return isAccessible
    }

    func writePositions(_ positions: [String: Int]) {
        calls.append("writePositions \(positions.count)")
    }

    func resolveKey(
        for item: MenuBarItem, existingKeys _: [String], positions _: [String: Int], liveItems _: [MenuBarItem]
    ) -> String? {
        calls.append("resolveKey")
        return "status:\(item.title ?? "")"
    }

    func parseStatusKey(_ key: String) -> PositionStatusKey? {
        calls.append("parseStatusKey \(key)")
        return PositionStatusKey(owner: "com.example", identifier: key)
    }

    func isParkedWeight(_ weight: Int) -> Bool {
        calls.append("isParkedWeight"); return weight > 1000
    }

    func isProvenAbsent(_ key: String) -> Bool {
        calls.append("isProvenAbsent"); return key == "gone"
    }

    func move(
        item _: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool
    ) -> Bool {
        calls.append("move"); return true
    }

    func applyOrder(desiredOrder: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        calls.append("applyOrder"); return desiredOrder
    }

    func respaceOrder(desiredOrder: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        calls.append("respaceOrder"); return desiredOrder
    }

    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        calls.append("breakTiedSiblingWeights"); return ["tied"]
    }

    func applyControlItemOrder(desiredOrder _: [MenuBarItem], opaqueVisibleKeys: [String], liveItems _: [MenuBarItem]) -> [String] {
        calls.append("applyControlItemOrder"); return opaqueVisibleKeys
    }

    func recordAbsenceEvidence(seen: Set<String>, blank _: Set<String>) -> Set<String> {
        calls.append("recordAbsenceEvidence")
        return seen
    }

    func resetAbsenceEvidence() {
        calls.append("resetAbsenceEvidence")
    }
}
