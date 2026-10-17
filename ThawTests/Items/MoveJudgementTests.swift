//
//  MoveJudgementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// A move whose result the bar can't show is set aside, not scored as a failure.
@Suite("Move judgement")
struct MoveJudgementTests {
    private static func item(_ bundle: String, _ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: windowID, ownerPID: pid_t(windowID), sourcePID: pid_t(windowID),
            bounds: CGRect(x: CGFloat(windowID) * 30, y: 3, width: 24, height: 24), title: title, isOnScreen: true
        )
    }

    @Test("A repaired item was applied")
    func repairedIsApplied() {
        #expect(MoveJudgement.judge(repaired: true, itemCountBefore: 20, itemCountAfter: 19, ownerIconCount: 3) == .applied)
    }

    @Test("A sole icon that didn't move was not applied")
    func soleIconUnapplied() {
        #expect(MoveJudgement.judge(repaired: false, itemCountBefore: 20, itemCountAfter: 20, ownerIconCount: 1) == .unapplied)
    }

    @Test("An icon whose app owns another can't be judged")
    func sharedOwnerUnjudgeable() {
        #expect(MoveJudgement.judge(repaired: false, itemCountBefore: 20, itemCountAfter: 20, ownerIconCount: 2)
            == .unjudgeable(.sharedOwner))
    }

    @Test("A bar that gained or lost an item meanwhile can't be judged")
    func itemCountChangeUnjudgeable() {
        #expect(MoveJudgement.judge(repaired: false, itemCountBefore: 20, itemCountAfter: 21, ownerIconCount: 1)
            == .unjudgeable(.itemCountChanged))
        #expect(MoveJudgement.judge(repaired: false, itemCountBefore: 20, itemCountAfter: 18, ownerIconCount: 2)
            == .unjudgeable(.itemCountChanged))
    }

    @Test("Owner icons count the app's items, not other apps' or Thaw's controls")
    func ownerIconCount() {
        let droppy = Self.item("iordv.Droppy", "DroppyMenuBar", windowID: 1)
        let items = [
            droppy,
            Self.item("iordv.Droppy", "LiquidPlayerMenuBar", windowID: 2),
            Self.item("com.example.Other", "Item-0", windowID: 3),
        ]
        #expect(MoveJudgement.ownerIconCount(of: droppy, among: items) == 2)
        #expect(MoveJudgement.ownerIconCount(of: items[2], among: items) == 1)
    }

    @Test("Not applied counts a strike toward suppression")
    func unappliedStrikes() {
        var breaker = BoundaryRepairBreaker<String>()
        let outcome = breaker.record(.unapplied, for: "a", tripLimit: 3)
        #expect(outcome.trips == 1)
        #expect(!breaker.isSuppressed("a"))
    }

    @Test("Can't judge sets the item aside at once, with no strike")
    func unjudgeableSetsAside() {
        var breaker = BoundaryRepairBreaker<String>()
        let outcome = breaker.record(.unjudgeable(.sharedOwner), for: "a", tripLimit: 3)
        #expect(outcome.trips == 0)
        #expect(breaker.isSuppressed("a"))
        #expect(breaker.trips(for: "a") == 0)
    }

    @Test("Applied clears the count")
    func appliedClears() {
        var breaker = BoundaryRepairBreaker<String>()
        breaker.record(.unapplied, for: "a", tripLimit: 3)
        breaker.record(.applied, for: "a", tripLimit: 3)
        #expect(breaker.trips(for: "a") == 0)
        #expect(!breaker.isSuppressed("a"))
    }
}
