//
//  MenuBarTooltipGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

struct MenuBarTooltipGeometryTests {
    private let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let lower = CGRect(x: 2560, y: 290, width: 1710, height: 1107)

    @Test("Tooltip selection and a refreshed anchor follow the mirrored seat")
    func mirroredTargetAndFreshAnchor() throws {
        let pointer = CGPoint(x: 4122, y: 307)
        let entries: [(windowID: CGWindowID, bounds: CGRect)] = [(7, CGRect(x: 2400, y: 5, width: 24, height: 24))]
        let target = try #require(MenuBarTooltipGeometry.target(
            at: pointer, entries: entries,
            destinationDisplay: lower, displayBounds: [main, lower], laneMinX: 3500
        ))
        #expect(target.windowID == 7)
        #expect(target.bounds == CGRect(x: 4110, y: 295, width: 24, height: 24))
        let freshEntries: [(windowID: CGWindowID, bounds: CGRect)] = [(7, CGRect(x: 2404, y: 5, width: 24, height: 24))]
        let fresh = try #require(MenuBarTooltipGeometry.target(
            at: pointer, entries: freshEntries,
            destinationDisplay: lower, displayBounds: [main, lower], laneMinX: 3500
        ))
        #expect(fresh.bounds == CGRect(x: 4114, y: 295, width: 24, height: 24))
    }

    @Test("An overflowed or removed seat cannot acquire a tooltip")
    func undrawnTargetIsExcluded() {
        let bounds = CGRect(x: 2400, y: 5, width: 24, height: 24)
        #expect(MenuBarTooltipGeometry.target(
            at: CGPoint(x: 2412, y: 17), entries: [(7, bounds)],
            destinationDisplay: main, displayBounds: [main, lower], laneMinX: 2450
        ) == nil)
        #expect(MenuBarTooltipGeometry.target(
            at: CGPoint(x: 4122, y: 307), entries: [],
            destinationDisplay: lower, displayBounds: [main, lower], laneMinX: nil
        ) == nil)
    }
}
