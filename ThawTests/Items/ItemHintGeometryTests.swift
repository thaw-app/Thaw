//
//  ItemHintGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

struct ItemHintGeometryTests {
    private let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let lower = CGRect(x: 0, y: 1440, width: 1710, height: 1107)

    @Test("Hint targets on a display below the main display are retained")
    func lowerDisplayTargets() {
        let bounds = CGRect(x: 1500, y: 1445, width: 24, height: 24)
        #expect(ItemHintGeometry.frame(
            bounds, on: lower, displays: [main, lower], barHeight: 34, laneMinX: nil
        ) == bounds)
        let above = CGRect(x: -1710, y: -1107, width: 1710, height: 1107)
        let upperSeat = CGRect(x: -100, y: -1102, width: 24, height: 24)
        #expect(ItemHintGeometry.frame(
            upperSeat, on: above, displays: [main, above], barHeight: 34, laneMinX: nil
        ) == upperSeat)
        for invalid in [CGRect.zero, CGRect(x: -1, y: 5, width: 24, height: 24), CGRect(x: 1500, y: 2400, width: 24, height: 24)] {
            #expect(ItemHintGeometry.frame(
                invalid, on: lower, displays: [main, lower], barHeight: 34, laneMinX: nil
            ) == nil)
        }
    }

    @Test("A mirrored hint uses the drawn seat, not the reported x coordinate")
    func mirroredBadgeSeat() {
        let bounds = CGRect(x: 2400, y: 5, width: 24, height: 24)
        #expect(ItemHintGeometry.frame(
            bounds, on: lower, displays: [main, lower], barHeight: 34, laneMinX: 900
        ) == CGRect(x: 1550, y: 1445, width: 24, height: 24))
        #expect(ItemHintGeometry.frame(
            bounds, on: lower, displays: [main, lower], barHeight: 34, laneMinX: 1600
        ) == nil)
        #expect(ItemHintGeometry.frame(
            bounds, on: main, displays: [main, lower], barHeight: 34, laneMinX: nil
        ) == bounds)
    }
}
