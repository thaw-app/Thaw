//
//  DrawnBarHitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

/// A click over an icon the bar draws is not empty space, even when the walk
/// could not read the app that owns it.
@Suite("Drawn bar hit test")
struct DrawnBarHitTests {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let entries = [
        MenuBarAgentWindow.Entry(ownerPID: 500, frame: CGRect(x: 1300, y: 3, width: 24, height: 24)),
        MenuBarAgentWindow.Entry(ownerPID: 42, frame: CGRect(x: 1400, y: 3, width: 35, height: 24)),
    ]

    private func contains(_ point: CGPoint, laneMinX: CGFloat? = nil) -> Bool {
        HIDEventManager.drawnBarContains(
            point, entries: entries, ownPID: 42, destinationDisplay: display, displayBounds: [display], laneMinX: laneMinX
        )
    }

    @Test("A click on a drawn icon is over an item")
    func clickOnDrawnIcon() {
        #expect(contains(CGPoint(x: 1310, y: 15)))
    }

    @Test("A click above the icon's frame but inside the bar still counts")
    func clickAboveTheFrame() {
        #expect(contains(CGPoint(x: 1310, y: 1)))
    }

    @Test("A click between icons is not over an item")
    func clickBetweenIcons() {
        #expect(!contains(CGPoint(x: 1350, y: 15)))
    }

    @Test("Thaw's own items are left to their own checks")
    func ownItemsAreSkipped() {
        #expect(!contains(CGPoint(x: 1410, y: 15)))
    }

    @Test("An icon left of the item lane is in the overflow menu, not on the bar")
    func iconBeforeTheLane() {
        #expect(!contains(CGPoint(x: 1310, y: 15), laneMinX: 1350))
    }

    @Test("A frame too wide to be an item does not swallow the bar")
    func oversizedFrame() {
        let wide = [MenuBarAgentWindow.Entry(ownerPID: 500, frame: CGRect(x: 0, y: 0, width: 1920, height: 30))]
        #expect(!HIDEventManager.drawnBarContains(
            CGPoint(x: 900, y: 15), entries: wide, ownPID: 42, destinationDisplay: display, displayBounds: [display], laneMinX: nil
        ))
    }
}
