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

    @Test
    func anOffScreenSavedEntryKeepsItsSlotWhenOnScreenItemsReorder() {
        let merged = LayoutEditorOrder.mergingAchievableOrder(
            ["c", "b", "a"],
            into: ["a", "parked", "b", "c"]
        )
        #expect(merged == ["c", "parked", "b", "a"])
    }

    @Test
    func aNoOpProjectionLeavesTheSavedOrderUntouched() {
        let saved = ["a", "parked", "b", "tail"]
        #expect(LayoutEditorOrder.mergingAchievableOrder(["a", "b"], into: saved) == saved)
    }

    @Test
    func anEntryMissingFromTheSavedOrderFollowsItsOnScreenNeighbour() {
        let merged = LayoutEditorOrder.mergingAchievableOrder(
            ["a", "new", "b"],
            into: ["a", "parked", "b"]
        )
        #expect(merged == ["a", "new", "parked", "b"])
    }

    @Test
    func anEntryMissingFromTheSavedOrderWithNoPredecessorGoesFirst() {
        let merged = LayoutEditorOrder.mergingAchievableOrder(["new", "a"], into: ["parked", "a"])
        #expect(merged == ["new", "parked", "a"])
    }

    @Test
    func anEmptySavedOrderTakesTheProjection() {
        #expect(LayoutEditorOrder.mergingAchievableOrder(["a", "b"], into: []) == ["a", "b"])
    }

    private func id(_ item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }

    @Test
    func anOffScreenLiveItemKeepsItsSlotInTheCommittedItems() {
        let a = LayoutEditorWorld.item("A")
        let parked = LayoutEditorWorld.item("Parked")
        let b = LayoutEditorWorld.item("B")
        let items = LayoutEditorOrder.itemsMergingAchievableOrder(
            [b.uniqueIdentifier, a.uniqueIdentifier],
            into: [id(a), id(parked), id(b)],
            candidates: [a, parked, b]
        )
        #expect(items.map(\.uniqueIdentifier) == [b, parked, a].map(\.uniqueIdentifier))
    }

    @Test
    func anIdentifierWithNoLiveItemIsDropped() {
        let a = LayoutEditorWorld.item("A")
        let items = LayoutEditorOrder.itemsMergingAchievableOrder(
            [a.uniqueIdentifier],
            into: ["gone", id(a)],
            candidates: [a]
        )
        #expect(items.map(\.uniqueIdentifier) == [a.uniqueIdentifier])
    }

    @Test
    func aRawSpellingMatchesItsSavedCanonicalEntry() throws {
        // Rectangle's old AppKit placeholder title canonicalizes to Item-0.
        let raw = "com.knollsoft.Rectangle:_NS:12"
        let rectangle = LayoutEditorWorld.item(
            MenuBarItemTag(namespace: .string("com.knollsoft.Rectangle"), title: "Item-0", instanceIndex: 0)
        )
        let b = LayoutEditorWorld.item("B")
        try #require(MenuBarItemTag.canonicalPersistentIdentifier(raw) == id(rectangle))

        let items = LayoutEditorOrder.itemsMergingAchievableOrder(
            [b.uniqueIdentifier, raw],
            into: [id(rectangle), id(b)],
            candidates: [rectangle, b]
        )
        #expect(items.map(\.uniqueIdentifier) == [b, rectangle].map(\.uniqueIdentifier))
    }

    @Test
    func aRepeatedCandidateIsListedOnce() {
        let a = LayoutEditorWorld.item("A")
        let items = LayoutEditorOrder.itemsMergingAchievableOrder(
            [a.uniqueIdentifier],
            into: [id(a)],
            candidates: [a, a]
        )
        #expect(items.count == 1)
    }

    @Test
    func aNewcomerBetweenNamedItemsKeepsItsSlot() {
        let completed = LayoutEditorOrder.completingOrder(["a", "b", "c"], withLive: ["a", "new", "b", "c"])
        #expect(completed == ["a", "new", "b", "c"])
    }

    @Test
    func aNewcomerBeforeEveryNamedItemGoesFirst() {
        let completed = LayoutEditorOrder.completingOrder(["a", "b"], withLive: ["new", "a", "b"])
        #expect(completed == ["new", "a", "b"])
    }

    @Test
    func newcomersInARunStayInLiveOrder() {
        let completed = LayoutEditorOrder.completingOrder(["b", "a"], withLive: ["a", "n1", "n2", "b"])
        #expect(completed == ["b", "a", "n1", "n2"])
    }

    @Test
    func aSavedEntryWithNoLiveItemStaysWhereItIs() {
        let completed = LayoutEditorOrder.completingOrder(["a", "gone", "b"], withLive: ["a", "b", "new"])
        #expect(completed == ["a", "gone", "b", "new"])
    }

    @Test
    func completionMatchesAnIdentifierByItsCanonicalSpelling() {
        let spelled = "com.bjango.istatmenus-setapp.status:CPU 42%"
        let live = "com.bjango.istatmenus-setapp.status:CPU 43%"
        let completed = LayoutEditorOrder.completingOrder([spelled, "b"], withLive: [live, "new", "b"])
        #expect(completed == [spelled, "new", "b"])
    }

    @Test
    func anOrderThatNamesEveryLiveItemIsReturnedUnchanged() {
        #expect(LayoutEditorOrder.completingOrder(["b", "a"], withLive: ["a", "b"]) == ["b", "a"])
        #expect(LayoutEditorOrder.completingOrder(["a", "b"], withLive: []) == ["a", "b"])
    }
}
