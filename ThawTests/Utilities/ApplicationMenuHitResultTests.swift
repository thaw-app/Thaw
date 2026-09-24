//
//  ApplicationMenuHitResultTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Application menu hit result")
struct ApplicationMenuHitResultTests {
    /// A 1512-point-wide display with a 24-point menu bar.
    private let strip = CGRect(x: 0, y: 0, width: 1512, height: 24)

    /// Apple, Firefox, File, Edit laid out along the menu bar.
    private let onScreenMenus = [
        CGRect(x: 10, y: 0, width: 30, height: 24),
        CGRect(x: 40, y: 0, width: 60, height: 24),
        CGRect(x: 100, y: 0, width: 40, height: 24),
        CGRect(x: 140, y: 0, width: 40, height: 24),
    ]

    @Test("A click on a menu title is inside the application menu")
    func hitOnMenuTitle() {
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: onScreenMenus,
            mouseLocation: CGPoint(x: 120, y: 12),
            menuBarStrip: strip
        ) == true)
    }

    @Test("A click past the last menu is not inside the application menu")
    func missPastLastMenu() {
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: onScreenMenus,
            mouseLocation: CGPoint(x: 800, y: 12),
            menuBarStrip: strip
        ) == false)
    }

    @Test("Menu frames outside the menu bar are indeterminate (#1028)")
    func offScreenTreeIsIndeterminate() {
        // A self-built AX tree reporting menus inside the browser window.
        let windowMenus = onScreenMenus.map { $0.offsetBy(dx: 0, dy: 300) }
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: windowMenus,
            mouseLocation: CGPoint(x: 120, y: 12),
            menuBarStrip: strip
        ) == nil)
    }

    @Test("A menu tree partly outside the menu bar is indeterminate")
    func mixedTreeIsIndeterminate() {
        let mixed = [onScreenMenus[0], onScreenMenus[1].offsetBy(dx: 0, dy: 300)]
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: mixed,
            mouseLocation: CGPoint(x: 120, y: 12),
            menuBarStrip: strip
        ) == nil)
    }

    @Test("An empty menu tree is indeterminate")
    func emptyTreeIsIndeterminate() {
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: [],
            mouseLocation: CGPoint(x: 120, y: 12),
            menuBarStrip: strip
        ) == nil)
    }

    @Test("Without a known menu bar strip a miss stays a miss")
    func unknownStripKeepsMiss() {
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: [],
            mouseLocation: CGPoint(x: 120, y: 12),
            menuBarStrip: nil
        ) == false)
    }

    @Test("Menus on a secondary display are judged against that display's strip")
    func secondaryDisplayStrip() {
        let secondStrip = strip.offsetBy(dx: 1512, dy: 0)
        let secondMenus = onScreenMenus.map { $0.offsetBy(dx: 1512, dy: 0) }
        #expect(HIDEventManager.applicationMenuHitResult(
            childFrames: secondMenus,
            mouseLocation: CGPoint(x: 1512 + 800, y: 12),
            menuBarStrip: secondStrip
        ) == false)
    }
}
