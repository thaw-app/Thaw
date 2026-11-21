//
//  AppProcessApplicationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The tests run inside the app process, so `NSApp` here is the one Thaw launches with.
@MainActor
@Suite("The app process gives AppKit no Windows menu")
struct AppProcessApplicationTests {
    @Test("The app process is launched with the application object that drops the Windows menu")
    func launchesWithSubclass() {
        #expect(NSApp is AppProcessApplication)
    }

    @Test("SwiftUI's Window menu, or any other, never becomes the Windows menu")
    func windowsMenuStaysNil() {
        #expect(NSApp.windowsMenu == nil)
        NSApp.windowsMenu = NSMenu(title: "Window")
        #expect(NSApp.windowsMenu == nil)
    }

    @Test("Minimize keeps ⌘M in the main menu")
    func minimizeKeepsItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let minimize = mainMenu.items.compactMap(\.submenu).flatMap(\.items).first {
            $0.action == #selector(NSWindow.performMiniaturize(_:))
        }
        #expect(minimize?.keyEquivalent == "m")
    }
}
