//
//  ControlItemSeatingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel
import Testing

/// Manual mode writes only dividers at section boundaries without displacing members.
/// Full-ladder writes would reject user moves while rewriting the table on every reveal.
@Suite("Seating a control item between fixed members")
struct ControlItemSeatingTests {
    // MARK: Axis

    @Test("Two members are enough to read the axis")
    func axisFromMembers() {
        let descending = ControlItemSeating.axisAscends(members: [(100, -5000), (200, -5100)])
        #expect(descending == false)
        let ascending = ControlItemSeating.axisAscends(members: [(100, 5000), (200, 5100)])
        #expect(ascending == true)
    }

    @Test("One drifted member does not flip the whole reading")
    func axisSurvivesOneOutlier() {
        // Four members descending left to right, one of them stale and out of
        // line. The monotone vote keeps the majority reading.
        let members: [(x: CGFloat, weight: Int)] = [
            (100, -5000), (200, -5100), (300, -4000), (400, -5300),
        ]
        #expect(ControlItemSeating.axisAscends(members: members) == false)
    }

    @Test("Fewer than two weighted members is not enough evidence")
    func axisDeclinesWithoutEvidence() {
        #expect(ControlItemSeating.axisAscends(members: []) == nil)
        #expect(ControlItemSeating.axisAscends(members: [(100, -5000)]) == nil)
    }

    // MARK: Already correct

    @Test("A control between its neighbours is left alone on either axis")
    func settledControlsAreNotRewritten() {
        #expect(ControlItemSeating.isSeated(-5050, between: -5000, and: -5100, ascending: false))
        #expect(ControlItemSeating.isSeated(5050, between: 5000, and: 5100, ascending: true))
    }

    @Test("A control outside its neighbours is not seated")
    func misplacedControlsAreDetected() {
        #expect(!ControlItemSeating.isSeated(-4000, between: -5000, and: -5100, ascending: false))
        #expect(!ControlItemSeating.isSeated(9000, between: 5000, and: 5100, ascending: true))
        #expect(!ControlItemSeating.isSeated(nil, between: -5000, and: -5100, ascending: false))
    }

    @Test("A control at the end of the order only has to clear one neighbour")
    func oneSidedSeatingCounts() {
        #expect(ControlItemSeating.isSeated(-5200, between: -5100, and: nil, ascending: false))
        #expect(!ControlItemSeating.isSeated(-5000, between: -5100, and: nil, ascending: false))
    }

    // MARK: Choosing a seat

    @Test("The seat falls strictly between the two anchors")
    func seatLandsBetweenAnchors() throws {
        let seat = try #require(
            ControlItemSeating.seat(between: -5000, and: -5100, ascending: false, avoiding: [])
        )
        #expect(seat < -5000 && seat > -5100)
    }

    @Test("Anchors that contradict the axis decline", arguments: [true, false])
    func reversedAnchorsDecline(ascending: Bool) {
        let before = ascending ? 5200 : 5000
        let after = ascending ? 5000 : 5200
        #expect(
            ControlItemSeating.seat(between: before, and: after, ascending: ascending, avoiding: []) == nil
        )
    }

    @Test("Adjacent anchors leave no room, so the control stays put")
    func adjacentAnchorsDecline() {
        #expect(ControlItemSeating.seat(between: -5000, and: -5001, ascending: false, avoiding: []) == nil)
        #expect(ControlItemSeating.seat(between: 5000, and: 5000, ascending: true, avoiding: []) == nil)
    }

    @Test("An occupied midpoint steps aside without leaving the gap")
    func occupiedMidpointStepsAside() throws {
        let taken: Set<Int> = [-5050, -5049, -5051]
        let seat = try #require(
            ControlItemSeating.seat(between: -5000, and: -5100, ascending: false, avoiding: taken)
        )
        #expect(!taken.contains(seat))
        #expect(seat < -5000 && seat > -5100)
    }

    @Test("A gap whose every weight is taken declines rather than displace a member")
    func afullGapDeclines() {
        let taken = Set(-5010 ... -5000)
        #expect(ControlItemSeating.seat(between: -5000, and: -5010, ascending: false, avoiding: taken) == nil)
    }

    @Test("With one neighbour the seat steps a full spacing past it")
    func oneSidedSeatStepsOut() {
        #expect(
            ControlItemSeating.seat(between: -5100, and: nil, ascending: false, avoiding: [])
                == -5100 - ControlItemSeating.spacing
        )
        #expect(
            ControlItemSeating.seat(between: nil, and: 5100, ascending: true, avoiding: [])
                == 5100 - ControlItemSeating.spacing
        )
    }

    @Test("With no neighbours at all there is nothing to seat against")
    func noAnchorsDecline() {
        #expect(ControlItemSeating.seat(between: nil, and: nil, ascending: false, avoiding: []) == nil)
    }
}
