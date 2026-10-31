//
//  ClosureMenuItemTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit
import Testing
import ThawUI

@MainActor
struct ClosureMenuItemTests {
    @Test func choosingTheItemRunsItsClosure() throws {
        var runs = 0
        let item = ClosureMenuItem(title: "Copy") { runs += 1 }
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        target.perform(action)
        target.perform(action)
        #expect(runs == 2)
        #expect(item.title == "Copy")
        #expect(item.isEnabled)
    }

    @Test func anItemCanStartOff() {
        #expect(!ClosureMenuItem(title: "Paste", isEnabled: false) {}.isEnabled)
    }

    @Test func aMenuKeepsEachItemAsItWasMade() {
        // Without an application a menu's update asks no item and turns every one off.
        _ = NSApplication.shared
        let menu = NSMenu()
        let off = ClosureMenuItem(title: "Paste", isEnabled: false) {}
        let on = ClosureMenuItem(title: "Copy") {}
        menu.addItem(off)
        menu.addItem(on)
        menu.update()
        #expect(menu.autoenablesItems)
        #expect(!off.isEnabled, "the menu's own check leaves it off")
        #expect(on.isEnabled)
    }

    @Test func anItemAnswersOnlyForItself() {
        let off = ClosureMenuItem(title: "Paste", isEnabled: false) {}
        #expect(!off.validateMenuItem(off))
        #expect(off.validateMenuItem(NSMenuItem()))
    }
}
