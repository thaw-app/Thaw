//
//  ClockActivationHitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

struct ClockActivationHitTests {
    private let bands = [
        CGRect(x: 0, y: 0, width: 1470, height: 40),
        CGRect(x: -1920, y: -200, width: 1920, height: 24),
    ]

    private func clock(bounds: CGRect) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Clock", instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 100,
            bounds: bounds,
            title: "Clock",
            isOnScreen: true
        )
    }

    @Test("An oversized AX clock frame cannot steal clicks below either menu bar")
    func clickBelowBarPassesThrough() {
        let item = clock(bounds: CGRect(x: 1370, y: 0, width: 100, height: 80))
        for point in [CGPoint(x: 1420, y: 45), CGPoint(x: -50, y: -171)] {
            #expect(HIDEventManager.systemClockItem(at: point, in: [item], menuBarBands: bands) == nil)
        }
    }

    @Test("A clock hit returns a frame clipped to its own display's bar")
    func clockBoundsAreClipped() {
        let item = clock(bounds: CGRect(x: 1370, y: 0, width: 100, height: 80))
        let hit = HIDEventManager.systemClockItem(at: CGPoint(x: 1420, y: 20), in: [item], menuBarBands: bands)
        #expect(hit?.bounds == CGRect(x: 1370, y: 0, width: 100, height: 40))
    }

    @Test("A mirrored clock uses the target display's origin and menu bar height")
    func mirroredClockUsesTargetBand() {
        let item = clock(bounds: CGRect(x: 1370, y: 0, width: 100, height: 40))
        let hit = HIDEventManager.systemClockItem(at: CGPoint(x: -50, y: -188), in: [item], menuBarBands: bands)
        #expect(hit?.tag == item.tag)
        #expect(hit?.bounds == CGRect(x: -100, y: -200, width: 100, height: 24))
    }

    @Test("A parked clock cannot seed a mirrored hit target")
    func parkedClockIsIgnored() {
        let item = clock(bounds: CGRect(x: 1370, y: 1000, width: 100, height: 40))
        #expect(HIDEventManager.systemClockItem(at: CGPoint(x: -50, y: -188), in: [item], menuBarBands: bands) == nil)
    }
}
