//
//  ThawBarItemPressTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// A held click on a Thaw Bar item did nothing once it passed half a second.
@Suite("Thaw Bar item press")
struct ThawBarItemPressTests {
    @Test("A press clicks however long it's held, as long as the pointer stays put")
    func holdingStillClicks() {
        var press = ThawBarItemPress()
        press.began(at: CGPoint(x: 100, y: 10))
        #expect(press.isActive)
        #expect(press.isClick(at: CGPoint(x: 103, y: 12)))
    }

    @Test("Moving five points turns the press into a drag of the panel")
    func movingDrags() {
        var press = ThawBarItemPress()
        press.began(at: CGPoint(x: 100, y: 10))
        #expect(!press.isClick(at: CGPoint(x: 105, y: 10)))
    }

    @Test("A release with no press, or after it ended, is not a click")
    func noPressNoClick() {
        var press = ThawBarItemPress()
        #expect(!press.isClick(at: .zero))
        press.began(at: .zero)
        press.ended()
        #expect(!press.isActive)
        #expect(!press.isClick(at: .zero))
    }
}
