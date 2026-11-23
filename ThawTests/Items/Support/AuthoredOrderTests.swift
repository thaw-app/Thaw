//
//  AuthoredOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

private func item(_ title: String, x: CGFloat, windowID: CGWindowID? = nil) -> MenuBarItem {
    ItemsFixture.item(title, x: x, windowID: windowID ?? UInt32(x) + 1)
}

/// A layout-pane drop commits its new order only after the move succeeds, so the record the
/// move reads still holds the pre-drag order; without the move applied nothing visibly changes.
@MainActor
@Suite("Authored order with a move applied")
struct AuthoredOrderApplyingDestinationTests {
    private let a = item("A", x: 0)
    private let b = item("B", x: 30)
    private let c = item("C", x: 60)
    private let d = item("D", x: 90)

    private var authored: [String] {
        [a, b, c, d].map(\.uniqueIdentifier)
    }

    @Test("Left of a target puts the item immediately before it")
    func leftOfTarget() {
        let order = AuthoredOrder.authoredOrder(authored, applying: .leftOfItem(b), to: d)
        #expect(order == [a, d, b, c].map(\.uniqueIdentifier))
    }

    @Test("Right of a target puts the item immediately after it")
    func rightOfTarget() {
        let order = AuthoredOrder.authoredOrder(authored, applying: .rightOfItem(c), to: a)
        #expect(order == [b, c, a, d].map(\.uniqueIdentifier))
    }

    @Test("A move the record already reflects leaves it unchanged")
    func alreadySatisfied() {
        let order = AuthoredOrder.authoredOrder(authored, applying: .rightOfItem(a), to: b)
        #expect(order == authored)
    }

    @Test("An item the record does not list yet is inserted at its destination")
    func arrivingItemIsInserted() {
        let record = [a, b, c].map(\.uniqueIdentifier)
        let order = AuthoredOrder.authoredOrder(record, applying: .leftOfItem(c), to: d)
        #expect(order == [a, b, d, c].map(\.uniqueIdentifier))
    }

    @Test("A target outside the record leaves it untouched")
    func foreignTargetIsIgnored() {
        let outsider = item("Outsider", x: 500)
        let order = AuthoredOrder.authoredOrder(authored, applying: .leftOfItem(outsider), to: a)
        #expect(order == authored)
    }

    @Test("Targeting the item itself is a no-op")
    func selfTargetIsIgnored() {
        let order = AuthoredOrder.authoredOrder(authored, applying: .rightOfItem(b), to: b)
        #expect(order == authored)
    }

    @Test("Thaw's own control items are never laddered into a section")
    func controlItemsAreNeverApplied() {
        let control = MenuBarItem(
            tag: ControlItemIdentifier.visible.tag, windowID: 999, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 24), title: ControlItemIdentifier.visible.rawValue, isOnScreen: true
        )
        #expect(AuthoredOrder.authoredOrder(authored, applying: .leftOfItem(a), to: control) == authored)
        #expect(AuthoredOrder.authoredOrder(authored, applying: .leftOfItem(control), to: d) == authored)
    }

    @Test("The record never gains a duplicate")
    func noDuplicates() {
        let order = AuthoredOrder.authoredOrder(authored, applying: .leftOfItem(a), to: c)
        #expect(order.count == authored.count)
        #expect(Set(order).count == order.count)
    }
}

/// A multi-item drop seats its members one at a time, so a member must be allowed to anchor
/// on the member seated just before it, or the group lands in reverse.
@Suite("Authored predecessor for seating")
@MainActor
struct AuthoredPredecessorTests {
    private let x = item("X", x: 0)
    private let a = item("A", x: 30)
    private let b = item("B", x: 60)

    private var order: [MenuBarItem] {
        [x, a, b]
    }

    @Test("A member seated earlier in the same drop anchors the next one")
    func seatedMemberAnchorsTheNext() {
        let unseated = Set([b.uniqueIdentifier])
        let predecessor = AuthoredOrder.authoredPredecessor(of: b, in: order, excluding: unseated)
        #expect(predecessor?.uniqueIdentifier == a.uniqueIdentifier)
    }

    @Test("With nothing seated yet the first member anchors on the resident item")
    func firstMemberAnchorsOnResident() {
        let moving = Set([a, b].map(\.uniqueIdentifier))
        let predecessor = AuthoredOrder.authoredPredecessor(of: a, in: order, excluding: moving)
        #expect(predecessor?.uniqueIdentifier == x.uniqueIdentifier)
    }

    @Test("The first item in the order has no predecessor")
    func firstItemHasNoPredecessor() {
        let predecessor = AuthoredOrder.authoredPredecessor(of: x, in: order, excluding: [])
        #expect(predecessor == nil)
    }

    @Test("An item the order does not list has no predecessor")
    func unlistedItemHasNoPredecessor() {
        let outsider = item("Outsider", x: 500)
        let predecessor = AuthoredOrder.authoredPredecessor(of: outsider, in: order, excluding: [])
        #expect(predecessor == nil)
    }
}

/// The structural write 600 ms after a reveal can still miss cached members, and laddering a
/// partial walk scrambles the bar.
@MainActor
@Suite("Completing a partial reveal walk")
struct RevealWalkCompletionTests {
    private let a = item("A", x: 0, windowID: 1)
    private let b = item("B", x: 30, windowID: 2)
    private let c = item("C", x: 60, windowID: 3)

    @Test("Cached members are inserted at their last-known position")
    func missingMembersAreInsertedByFrame() {
        let completed = AuthoredOrder.completingPartialWalk([a, c], with: [a, b, c])
        #expect(completed.map(\.uniqueIdentifier) == [a, b, c].map(\.uniqueIdentifier))
    }

    @Test("A complete walk is returned as is")
    func completeWalkIsUntouched() {
        let completed = AuthoredOrder.completingPartialWalk([a, b, c], with: [a, b, c])
        #expect(completed.map(\.uniqueIdentifier) == [a, b, c].map(\.uniqueIdentifier))
    }

    @Test("Live geometry wins over the cached copy, even under a new window ID")
    func liveGeometryWins() {
        let relaunched = item("B", x: 300, windowID: 42)
        let completed = AuthoredOrder.completingPartialWalk([a, relaunched], with: [a, b, c])
        #expect(completed.map(\.uniqueIdentifier) == [a, c, relaunched].map(\.uniqueIdentifier))
        #expect(completed[2].windowID == 42)
        #expect(completed[2].bounds.minX == 300)
    }

    @Test("An empty cache adds nothing")
    func emptyCacheAddsNothing() {
        #expect(AuthoredOrder.completingPartialWalk([a], with: []).count == 1)
    }
}
