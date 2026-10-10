//
//  ThawBarIconAnchorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Parked x = -1 or zero-height controls must not anchor the bar, which would clamp it to the left edge.
@Suite("Thaw Bar icon anchor")
struct ThawBarIconAnchorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test("The leading-edge sentinel is not a usable anchor")
    func rejectsParkedSentinel() {
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: -1, y: 0, width: 31, height: 24), screenFrame: screen))
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: -0.5, y: 0, width: 2, height: 0), screenFrame: screen))
    }

    @Test("A zero-height or zero-width frame is not a usable anchor")
    func rejectsDegenerateFrame() {
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 2360, y: 0, width: 35, height: 0), screenFrame: screen))
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 2360, y: 0, width: 0, height: 24), screenFrame: screen))
    }

    @Test("A real seat on the bar is a usable anchor")
    func acceptsRealSeat() {
        #expect(ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 1400, y: 0, width: 35, height: 24), screenFrame: screen))
    }

    @Test("A frame past the screen's right edge is not usable")
    func rejectsOffRightEdge() {
        #expect(!ThawBarPanel.isUsableThawIconAnchor(CGRect(x: 1450, y: 0, width: 35, height: 24), screenFrame: screen))
    }

    @Test("A real seat on a left display with negative coordinates is usable")
    func acceptsNegativeOriginSeat() {
        let leftScreen = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        #expect(ThawBarPanel.isUsableThawIconAnchor(CGRect(x: -400, y: 0, width: 24, height: 24), screenFrame: leftScreen))
    }
}
