//
//  StandInPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("A stand-in takes its original's slot only when it has no place yet")
struct StandInPlacementTests {
    private let standIn = "com.example.thaw.extra.timer:Thaw.Extra.Timer"
    private let original = "com.apple.menuextra.timer"

    @Test("A new stand-in follows its original")
    func newStandInFollowsOriginal() {
        let order = SystemExtraStandIn.orderPlacing(standIn, after: original, in: ["a", original, "b"])

        #expect(order == ["a", original, standIn, "b"])
    }

    @Test("A stand-in the user moved stays where it is")
    func movedStandInStaysPut() {
        let order = SystemExtraStandIn.orderPlacing(standIn, after: original, in: [standIn, "a", original, "b"])

        #expect(order == nil)
    }

    @Test("A stand-in already next to its original changes nothing")
    func adjacentStandInChangesNothing() {
        let order = SystemExtraStandIn.orderPlacing(standIn, after: original, in: ["a", original, standIn, "b"])

        #expect(order == nil)
    }

    @Test("An original in another section changes nothing")
    func originalInAnotherSectionChangesNothing() {
        let order = SystemExtraStandIn.orderPlacing(standIn, after: original, in: ["a", "b"])

        #expect(order == nil)
    }
}
