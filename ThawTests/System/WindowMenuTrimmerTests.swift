//
//  WindowMenuTrimmerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
struct WindowMenuTrimmerTests {
    private func mainMenu() -> (main: NSMenu, window: NSMenu) {
        let main = NSMenu(title: "Main")
        let window = NSMenu(title: "Window")
        for title in ["Thaw", "Edit", "Window", "Help"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = title == "Window" ? window : NSMenu(title: title)
            main.addItem(item)
        }
        return (main, window)
    }

    @Test
    func `with no window open the Window menu comes off, and a window puts it back where it was`() {
        let trimmer = WindowMenuTrimmer()
        let (main, window) = mainMenu()
        trimmer.update(anyWindowOpen: false, mainMenu: main, windowsMenu: window)
        #expect(trimmer.isDetached)
        #expect(main.items.map(\.title) == ["Thaw", "Edit", "Help"])
        trimmer.update(anyWindowOpen: true, mainMenu: main, windowsMenu: window)
        #expect(!trimmer.isDetached)
        #expect(main.items.map(\.title) == ["Thaw", "Edit", "Window", "Help"])
    }

    @Test
    func `closing twice detaches once, and a menu SwiftUI rebuilt meanwhile isn't doubled`() {
        let trimmer = WindowMenuTrimmer()
        let (main, window) = mainMenu()
        trimmer.update(anyWindowOpen: false, mainMenu: main, windowsMenu: window)
        trimmer.update(anyWindowOpen: false, mainMenu: main, windowsMenu: window)
        #expect(main.items.count == 3)
        let rebuilt = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        rebuilt.submenu = NSMenu(title: "Window")
        main.insertItem(rebuilt, at: 2)
        trimmer.update(anyWindowOpen: true, mainMenu: main, windowsMenu: window)
        #expect(main.items.filter { $0.title == "Window" }.count == 1)
    }

    @Test
    func `the Window menu is found by its Minimize item when AppKit doesn't name it`() {
        let (main, window) = mainMenu()
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        #expect(WindowMenuTrimmer.windowsMenu(in: main) === window)
        let trimmer = WindowMenuTrimmer()
        trimmer.update(anyWindowOpen: false, mainMenu: main, windowsMenu: nil)
        #expect(trimmer.isDetached)
    }

    @Test
    func `a replaced main menu is trimmed afresh`() {
        let trimmer = WindowMenuTrimmer()
        let (first, firstWindow) = mainMenu()
        trimmer.update(anyWindowOpen: false, mainMenu: first, windowsMenu: firstWindow)
        let (second, secondWindow) = mainMenu()
        trimmer.update(anyWindowOpen: false, mainMenu: second, windowsMenu: secondWindow)
        #expect(second.items.map(\.title) == ["Thaw", "Edit", "Help"])
    }

    @Test
    func `without a known Window menu nothing is removed`() {
        let trimmer = WindowMenuTrimmer()
        let (main, _) = mainMenu()
        trimmer.update(anyWindowOpen: false, mainMenu: main, windowsMenu: nil)
        #expect(!trimmer.isDetached)
        #expect(main.items.count == 4)
    }
}
