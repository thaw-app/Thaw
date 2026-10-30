//
//  WindowLevelPredicatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Window level predicates")
struct WindowLevelPredicatesTests {
    private let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private func window(pid: pid_t, layer: Int) -> WindowInfo {
        WindowInfo(windowID: 1, ownerPID: pid, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: layer)
    }

    @Test("Only the exact pop-up menu level counts as an open menu")
    func popUpMenuLevel() {
        #expect(WindowLevelPredicates.isPopUpMenu(layer: menuLevel))
        #expect(!WindowLevelPredicates.isPopUpMenu(layer: menuLevel - 1))
        #expect(!WindowLevelPredicates.isPopUpMenu(layer: 0))
    }

    @Test("Another process's menu-level window is an open foreign menu")
    func foreignMenu() {
        #expect(WindowLevelPredicates.isForeignPopUpMenuOpen(in: [window(pid: 0, layer: 0), window(pid: ownPID + 1, layer: menuLevel)]))
    }

    @Test("Thaw's own menus and other processes' ordinary windows do not count")
    func ownOrOrdinaryWindows() {
        #expect(!WindowLevelPredicates.isForeignPopUpMenuOpen(in: []))
        #expect(!WindowLevelPredicates.isForeignPopUpMenuOpen(in: [window(pid: ownPID, layer: menuLevel)]))
        #expect(!WindowLevelPredicates.isForeignPopUpMenuOpen(in: [window(pid: ownPID + 1, layer: menuLevel - 1)]))
    }
}
