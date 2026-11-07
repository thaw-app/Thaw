//
//  ThawBarItemPressTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
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

/// The click view reports a press as it starts and clears it on release, then clicks.
@MainActor
@Suite("Thaw Bar item click view")
struct ThawBarItemClickViewTests {
    @Test("A press in place shows pressed, then clicks on release")
    func pressThenRelease() throws {
        var clicks = 0
        var pressed: [Bool] = []
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.press"), title: "Press", instanceIndex: 0),
            windowID: 3, ownerPID: 42, sourcePID: 42,
            bounds: CGRect(x: 0, y: 0, width: 22, height: 22), title: "Press", isOnScreen: true
        )
        let view = ThawBarItemClickView.Represented(
            item: item, tooltipDelay: 1,
            leftClickAction: { clicks += 1 }, rightClickAction: { /* Not exercised here. */ },
            onHover: { _ in /* Not exercised here. */ }
        )
        view.onPress = { pressed.append($0) }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        try view.mouseDown(with: event(.leftMouseDown))
        try view.mouseDragged(with: event(.leftMouseDragged))
        try view.mouseUp(with: event(.leftMouseUp))
        #expect(pressed == [true, false])
        #expect(clicks == 1)
    }
}
