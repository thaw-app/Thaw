//
//  DrawnBarFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

/// The frame MenuBarAgent's drawn bar vouches for, for an app that answers no AX.
@Suite("Drawn bar frames")
struct DrawnBarFrameTests {
    private static func entry(_ owner: pid_t, x: CGFloat, width: CGFloat) -> MenuBarAgentWindow.Entry {
        MenuBarAgentWindow.Entry(ownerPID: owner, frame: CGRect(x: x, y: 0, width: width, height: 30))
    }

    @Test("Floe's one entry lines up with its item")
    func oneEntry() {
        let bounds = CGRect(x: 1600, y: 3, width: 38, height: 24)
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 919, bounds: bounds, in: [Self.entry(919, x: 1600, width: 38)]) == bounds)
    }

    @Test("f.lux draws two entries for one item; the one at the item's place is used")
    func twoEntriesOneItem() {
        let bounds = CGRect(x: 1560.5, y: 3, width: 31, height: 24)
        let drawn = [Self.entry(944, x: 1529, width: 31), Self.entry(944, x: 1560, width: 31)]
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 944, bounds: bounds, in: drawn)
            == CGRect(x: 1560, y: 3, width: 31, height: 24))
    }

    @Test("Another app's entry over the item leaves it unplaced")
    func otherOwnerOverlaps() {
        let bounds = CGRect(x: 1600, y: 3, width: 38, height: 24)
        let drawn = [Self.entry(919, x: 1600, width: 38), Self.entry(5, x: 1605, width: 38)]
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 919, bounds: bounds, in: drawn) == nil)
    }

    @Test("No entry of the owner at the item's place leaves it unplaced")
    func noMatch() {
        let bounds = CGRect(x: 1600, y: 3, width: 38, height: 24)
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 919, bounds: bounds, in: [Self.entry(919, x: 1700, width: 38)]) == nil)
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 919, bounds: bounds, in: [Self.entry(919, x: 1600, width: 60)]) == nil)
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 919, bounds: bounds, in: []) == nil)
        #expect(AXGeometryCatalog.drawnFrame(ownerPID: 919, bounds: bounds, in: [Self.entry(919, x: 1602, width: 38)]) == nil,
                "two points off is not the same place; no picture beats a wrong one")
    }
}
