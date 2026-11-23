//
//  MenuBarOverlayPanelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Panels made here are never ordered in, and each test closes its own.
@MainActor
@Suite("Menu bar overlay panels")
struct MenuBarOverlayPanelTests {
    @Test("A clear overlay lets clicks through and stays out of focus, captures and Spaces switching")
    func clearOverlay() {
        let panel = NSPanel.menuBarOverlay(opaque: false, absorbsClicks: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.isFloatingPanel)
        #expect(panel.animationBehavior == .none)
        #expect(!panel.hasShadow)
        #expect(panel.level == NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1))
        #expect(panel.collectionBehavior == [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary])
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canHide)
        #expect(panel.sharingType == .none)
        #expect(!panel.isVisible)
    }

    @Test("An opaque overlay keeps its background and absorbs clicks")
    func opaqueOverlay() {
        let panel = NSPanel.menuBarOverlay(opaque: true, absorbsClicks: true)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        #expect(panel.isOpaque)
        #expect(panel.backgroundColor != .clear)
        #expect(!panel.ignoresMouseEvents)
    }

    @Test("Registering adds the panel's window ID to the overlay set and unregistering removes it")
    func registration() throws {
        let panel = NSPanel.menuBarOverlay(opaque: false, absorbsClicks: false)
        panel.isReleasedWhenClosed = false
        defer {
            panel.unregisterAsMenuBarOverlay()
            panel.close()
        }
        let windowID = try #require(panel.windowServerID)
        #expect(windowID == CGWindowID(panel.windowNumber))
        panel.registerAsMenuBarOverlay()
        #expect(MenuBarOverlayWindows.current.contains(windowID))
        panel.unregisterAsMenuBarOverlay()
        #expect(!MenuBarOverlayWindows.current.contains(windowID))
    }

    @Test("A window with no window server backing registers nothing")
    func unbackedWindow() {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        #expect(window.windowServerID == nil)
        let before = MenuBarOverlayWindows.current
        window.registerAsMenuBarOverlay()
        #expect(MenuBarOverlayWindows.current == before)
        window.unregisterAsMenuBarOverlay()
        #expect(MenuBarOverlayWindows.current == before)
    }
}

@Suite("Window server IDs")
struct WindowServerIDTests {
    @Test("A window number in CGWindowID range converts")
    func validWindowNumber() {
        #expect(NSWindow.windowServerID(forWindowNumber: 2_652_381_101) == 2_652_381_101)
        #expect(NSWindow.windowServerID(forWindowNumber: Int(UInt32.max)) == UInt32.max)
    }

    @Test("Zero, negative and synthetic window numbers have no ID", arguments: [
        0, -1, 0x8_0000_0000, 0x9_0000_0000, Int(UInt32.max) + 1, Int.max,
    ])
    func invalidWindowNumbers(_ windowNumber: Int) {
        #expect(NSWindow.windowServerID(forWindowNumber: windowNumber) == nil)
    }
}
