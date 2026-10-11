//
//  LayoutEditorOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct LayoutEditorOrderTests {
    private typealias Unit = LayoutEditorOrder.Unit

    private func single(_ id: String) -> Unit {
        Unit(id: id, memberIDs: [id])
    }

    @Test
    func aScatteredGroupBecomesOneUnitAtItsFirstMember() {
        let units = LayoutEditorOrder.units(
            itemIDs: ["a", "g1", "b", "g2", "c"],
            groups: [(id: "droppy", memberIndices: [1, 3])]
        )
        #expect(units == [single("a"), Unit(id: "group:droppy", memberIDs: ["g1", "g2"]), single("b"), single("c")])
    }

    @Test
    func aGroupOfOneStaysASingleItem() {
        let units = LayoutEditorOrder.units(itemIDs: ["a", "b"], groups: [(id: "solo", memberIndices: [1])])
        #expect(units == [single("a"), single("b")])
    }

    @Test
    func aDropBeforeAnotherUnitReordersTheSection() throws {
        let units: [MenuBarSectionName: [Unit]] = [.visible: [single("a"), single("b"), single("c")]]
        let change = try #require(LayoutEditorOrder.change(moving: "c", in: units, to: .visible, before: "a"))
        #expect(change.itemIDs(in: .visible) == ["c", "a", "b"])
        #expect(change.source == .visible)
        #expect(change.target == .visible)
    }

    @Test
    func aGroupCrossesSectionsAsABlock() throws {
        let group = Unit(id: "group:droppy", memberIDs: ["g1", "g2"])
        let units: [MenuBarSectionName: [Unit]] = [.visible: [single("a"), group], .hidden: [single("h")]]
        let change = try #require(LayoutEditorOrder.change(moving: group.id, in: units, to: .hidden, before: nil))
        #expect(change.itemIDs(in: .visible) == ["a"])
        #expect(change.itemIDs(in: .hidden) == ["h", "g1", "g2"])
        #expect(change.movedIDs == ["g1", "g2"])
    }

    @Test
    func aDropThatMovesNothingIsNoChange() {
        let units: [MenuBarSectionName: [Unit]] = [.visible: [single("a"), single("b")]]
        #expect(LayoutEditorOrder.change(moving: "a", in: units, to: .visible, before: "b") == nil)
        #expect(LayoutEditorOrder.change(moving: "b", in: units, to: .visible, before: nil) == nil)
        #expect(LayoutEditorOrder.change(moving: "a", in: units, to: .visible, before: "a") == nil)
        #expect(LayoutEditorOrder.change(moving: "missing", in: units, to: .visible, before: nil) == nil)
    }

    @Test
    func theAuthoredOrderIsKeptOnlyWhileTheBarCatchesUp() {
        let limit = Duration.seconds(8)
        #expect(LayoutEditorOrder.keepsAuthoredOrder(authored: ["b", "a"], live: ["a", "b"], elapsed: .seconds(1), limit: limit))
        #expect(!LayoutEditorOrder.keepsAuthoredOrder(authored: ["b", "a"], live: ["b", "a"], elapsed: .seconds(1), limit: limit))
        #expect(!LayoutEditorOrder.keepsAuthoredOrder(authored: ["b", "a"], live: ["a", "b"], elapsed: .seconds(9), limit: limit))
        #expect(!LayoutEditorOrder.keepsAuthoredOrder(authored: ["b", "a"], live: ["a", "b", "c"], elapsed: .seconds(1), limit: limit))
    }
}
