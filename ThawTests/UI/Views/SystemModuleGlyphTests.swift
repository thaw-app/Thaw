//
//  SystemModuleGlyphTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A system module Thaw hid by switching it off is never drawn, so it shows its own symbol until it has a picture.
@MainActor
@Suite("System module glyphs")
struct SystemModuleGlyphTests {
    private func agentItem(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title, windowID: 3, instanceIndex: 0),
            windowID: 3,
            ownerPID: 0,
            sourcePID: nil,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: nil,
            isOnScreen: false
        )
    }

    @Test(
        "A module's symbol is found by any of its titles",
        arguments: [
            ("com.apple.menuextra.bluetooth", "bluetooth"),
            ("Bluetooth", "bluetooth"),
            ("com.apple.menuextra.wifi", "wifi"),
            ("com.apple.menuextra.airdrop", "airdrop"),
        ]
    )
    func symbolForModuleTitle(title: String, symbol: String) {
        #expect(SystemModuleGlyph.symbolName(forItemTitle: title) == symbol)
    }

    @Test("A title no module uses has no symbol")
    func unknownTitleHasNone() {
        #expect(SystemModuleGlyph.symbolName(forItemTitle: "com.example.unknown") == nil)
    }

    @Test("Bluetooth's symbol loads, though macOS keeps it out of the public set")
    func bluetoothLoads() throws {
        let image = try #require(SystemModuleGlyph.image(forItemTitle: "com.apple.menuextra.bluetooth"))
        #expect(image.isTemplate)
        #expect(NSImage(systemSymbolName: "bluetooth", accessibilityDescription: nil) == nil)
    }

    @Test("A Bluetooth item with no picture falls back to its own symbol, not the generic one")
    func fallbackUsesModuleSymbol() throws {
        let fallback = try #require(OverflowFallbackIcon.image(for: agentItem("com.apple.menuextra.bluetooth")))
        let module = try #require(SystemModuleGlyph.image(forItemTitle: "com.apple.menuextra.bluetooth"))
        let generic = try #require(NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil))
        #expect(fallback.tiffRepresentation == module.tiffRepresentation)
        #expect(fallback.tiffRepresentation != generic.tiffRepresentation)
    }

    @Test("A MenuBarAgent item that is no known module keeps the generic glyph")
    func unknownAgentItemKeepsGeneric() throws {
        let fallback = try #require(OverflowFallbackIcon.image(for: agentItem("live-activity-pill-x")))
        let generic = try #require(NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil))
        #expect(fallback.size == generic.size)
    }
}
