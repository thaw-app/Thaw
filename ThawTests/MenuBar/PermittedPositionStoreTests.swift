//
//  PermittedPositionStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("The permitted store passes every call to the store underneath")
struct PermittedPositionStoreTests {
    /// Records each call by name and answers with values a test can tell apart.
    private final class Spy: MenuBarPositionStoring {
        var calls: [String] = []

        func currentPositions() -> [String: Int] { calls.append("currentPositions"); return ["current": 1] }
        func readPositions() -> [String: Int] { calls.append("readPositions"); return ["read": 2] }
        func positionsDomainIsAccessible() -> Bool { calls.append("positionsDomainIsAccessible"); return true }
        func writePositions(_ positions: [String: Int]) { calls.append("writePositions \(positions.count)") }

        func resolveKey(
            for item: MenuBarItem, existingKeys _: [String], positions _: [String: Int], liveItems _: [MenuBarItem]
        ) -> String? {
            calls.append("resolveKey")
            return "status:\(item.title ?? "")"
        }

        func parseStatusKey(_ key: String) -> PositionStatusKey? { calls.append("parseStatusKey \(key)"); return nil }
        func isParkedWeight(_ weight: Int) -> Bool { calls.append("isParkedWeight"); return weight > 1000 }
        func isProvenAbsent(_ key: String) -> Bool { calls.append("isProvenAbsent"); return key == "gone" }

        func move(
            item _: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool
        ) -> Bool {
            calls.append("move"); return true
        }

        func move(
            item _: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem],
            experimentalSystemItemHiding _: Bool, mayRewriteAroundUnplaceableItems: Bool
        ) -> Bool {
            calls.append("move rewrite=\(mayRewriteAroundUnplaceableItems)"); return false
        }

        func applyOrder(desiredOrder: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
            calls.append("applyOrder"); return desiredOrder
        }

        func applyOrder(
            desiredOrder: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool,
            mayRewriteAroundUnplaceableItems: Bool
        ) -> [String] {
            calls.append("applyOrder rewrite=\(mayRewriteAroundUnplaceableItems)"); return desiredOrder.reversed()
        }

        func respaceOrder(desiredOrder: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
            calls.append("respaceOrder"); return desiredOrder
        }

        func respaceOrder(
            desiredOrder: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool,
            mayRewriteAroundUnplaceableItems: Bool
        ) -> [String] {
            calls.append("respaceOrder rewrite=\(mayRewriteAroundUnplaceableItems)"); return desiredOrder.reversed()
        }

        func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] { calls.append("breakTiedSiblingWeights"); return ["tied"] }

        func applyControlItemOrder(desiredOrder _: [MenuBarItem], opaqueVisibleKeys: [String], liveItems _: [MenuBarItem]) -> [String] {
            calls.append("applyControlItemOrder"); return opaqueVisibleKeys
        }

        func recordAbsenceEvidence(seen _: Set<String>, blank _: Set<String>) -> Set<String> { [] }
        func resetAbsenceEvidence() {}
    }

    private func item(_ name: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(name)"), title: name, instanceIndex: 0),
            windowID: 1, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24), title: name, isOnScreen: true
        )
    }

    private func permit() -> StoreWritePermit { .unsequenced("permitted store test") }

    @Test("Reads go straight through, with no permit")
    func reads() {
        let spy = Spy()
        let store = PermittedPositionStore(wrapping: spy)

        #expect(store.currentPositions() == ["current": 1])
        #expect(store.readPositions() == ["read": 2])
        #expect(store.positionsDomainIsAccessible())
        #expect(store.resolveKey(for: item("A"), existingKeys: [], positions: [:], liveItems: []) == "status:A")
        #expect(store.parseStatusKey("status:A") == nil)
        #expect(store.isParkedWeight(5000))
        #expect(!store.isParkedWeight(10))
        #expect(store.isProvenAbsent("gone"))
        #expect(!store.refusesOrdering)
        #expect(spy.calls == [
            "currentPositions", "readPositions", "positionsDomainIsAccessible", "resolveKey",
            "parseStatusKey status:A", "isParkedWeight", "isParkedWeight", "isProvenAbsent",
        ])
    }

    @Test("Each move reaches the matching move underneath and returns its answer")
    func moves() {
        let spy = Spy()
        let store = PermittedPositionStore(wrapping: spy)
        let a = item("A"), b = item("B")

        // A permit cannot be copied into the expectation macro, so each answer is taken first.
        let plain = store.move(item: a, to: .leftOfItem(b), liveItems: [a, b], experimentalSystemItemHiding: false, permit: permit())
        let rewriting = store.move(
            item: a, to: .rightOfItem(b), liveItems: [a, b], experimentalSystemItemHiding: true,
            mayRewriteAroundUnplaceableItems: true, permit: permit()
        )
        #expect(plain)
        #expect(!rewriting)
        #expect(spy.calls == ["move", "move rewrite=true"])
    }

    @Test("Each ordering write reaches the matching write underneath and returns what it changed")
    func orderingWrites() {
        let spy = Spy()
        let store = PermittedPositionStore(wrapping: spy)
        let order = ["a", "b"]

        let applied = store.applyOrder(desiredOrder: order, liveItems: [], experimentalSystemItemHiding: false, permit: permit())
        let appliedRewriting = store.applyOrder(
            desiredOrder: order, liveItems: [], experimentalSystemItemHiding: false,
            mayRewriteAroundUnplaceableItems: false, permit: permit()
        )
        let respaced = store.respaceOrder(desiredOrder: order, liveItems: [], experimentalSystemItemHiding: false, permit: permit())
        let respacedRewriting = store.respaceOrder(
            desiredOrder: order, liveItems: [], experimentalSystemItemHiding: false,
            mayRewriteAroundUnplaceableItems: true, permit: permit()
        )
        let untied = store.breakTiedSiblingWeights(liveItems: [], permit: permit())
        let controls = store.applyControlItemOrder(desiredOrder: [], opaqueVisibleKeys: ["k"], liveItems: [], permit: permit())
        #expect(applied == order)
        #expect(appliedRewriting == ["b", "a"])
        #expect(respaced == order)
        #expect(respacedRewriting == ["b", "a"])
        #expect(untied == ["tied"])
        #expect(controls == ["k"])
        store.writePositions(["a": 1, "b": 2], permit: permit())

        #expect(spy.calls == [
            "applyOrder", "applyOrder rewrite=false", "respaceOrder", "respaceOrder rewrite=true",
            "breakTiedSiblingWeights", "applyControlItemOrder", "writePositions 2",
        ])
    }

    @Test("Every write is counted under the door it came through")
    func writesAreCounted() {
        let store = PermittedPositionStore(wrapping: Spy())
        let key = "unsequenced(permitted store test)"
        let before = StoreWriteAudit.unsequenced[key, default: 0]

        store.writePositions([:], permit: permit())
        _ = store.breakTiedSiblingWeights(liveItems: [], permit: permit())
        _ = store.applyOrder(desiredOrder: [], liveItems: [], experimentalSystemItemHiding: false, permit: permit())

        #expect(StoreWriteAudit.unsequenced[key] == before + 3)
    }
}
