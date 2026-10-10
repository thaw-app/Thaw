//
//  NotificationCenterInputStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

struct NotificationCenterInputStateTests {
    @Test("A second deliberate shortcut is not dropped while a bridge is busy")
    func repeatedPresses() {
        var state = NotificationCenterInputState()
        for _ in 0 ..< 3 {
            #expect(state.key(type: .keyDown, code: 45, isRepeat: false, matches: true, shouldBridge: true) == .activate)
            #expect(state.key(type: .keyDown, code: 45, isRepeat: true, matches: true, shouldBridge: true) == .consume)
            #expect(state.key(type: .keyUp, code: 45, isRepeat: false, matches: false, shouldBridge: false) == .consume)
        }
    }

    @Test("Unrelated keys and their releases pass through during a claimed shortcut")
    func unrelatedKeys() {
        var state = NotificationCenterInputState()
        _ = state.key(type: .keyDown, code: 45, isRepeat: false, matches: true, shouldBridge: true)
        #expect(state.key(type: .keyDown, code: 8, isRepeat: false, matches: false, shouldBridge: true) == .passThrough)
        #expect(state.key(type: .keyUp, code: 8, isRepeat: false, matches: false, shouldBridge: true) == .passThrough)
    }

    @Test("A lost release does not swallow the next deliberate press")
    func missingRelease() {
        var state = NotificationCenterInputState()
        for _ in 0 ..< 2 {
            #expect(state.key(type: .keyDown, code: 45, isRepeat: false, matches: true, shouldBridge: true) == .activate)
        }
    }

    @Test("Native shortcuts pass through when no restriction needs bridging")
    func unrestrictedKeys() {
        var state = NotificationCenterInputState()
        #expect(state.key(type: .keyDown, code: 45, isRepeat: false, matches: true, shouldBridge: false) == .passThrough)
        #expect(state.key(type: .keyUp, code: 45, isRepeat: false, matches: true, shouldBridge: false) == .passThrough)
    }

    @Test("A completed clock gesture keeps the original location")
    func clockClick() {
        var state = NotificationCenterInputState()
        let bounds = CGRect(x: -100, y: -200, width: 80, height: 30)
        let point = CGPoint(x: -60, y: -185)
        state.beginClockPress(at: point, bounds: bounds)
        #expect(state.hasClockPress)
        #expect(state.endClockPress(at: CGPoint(x: -61, y: -185)) == point)
        #expect(!state.hasClockPress)
        #expect(state.endClockPress(at: point) == nil)
    }

    @Test("Dragging away and returning does not activate Notification Center")
    func cancelledDrag() {
        var state = NotificationCenterInputState()
        let bounds = CGRect(x: 1800, y: 0, width: 100, height: 30)
        state.beginClockPress(at: bounds.center, bounds: bounds)
        state.dragClockPress(to: CGPoint(x: 1850, y: 100))
        #expect(state.endClockPress(at: bounds.center) == nil)
        #expect(!state.hasClockPress)
    }
}
