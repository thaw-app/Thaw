//
//  ThawHUDTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The confirmation capsule, shown and taken down within one main-actor turn so it never reaches the screen.
@Suite("Thaw HUD", .serialized)
@MainActor
struct ThawHUDTests {
    /// The HUD's panel, told apart from other windows by its level and click-through.
    private func hudPanels() -> [NSWindow] {
        NSApp.windows.filter { $0 is NSPanel && $0.level == .statusBar && $0.ignoresMouseEvents && $0.isVisible }
    }

    @Test("A capsule sits under the menu bar at the placement asked for, sized to its text")
    func placementAndSize() throws {
        let screen = try #require(NSScreen.screens.first)
        ThawHUD.dismiss()
        let before = Set(hudPanels().map(ObjectIdentifier.init))

        ThawHUD.show(symbol: "moon", text: "Zen on", on: screen, placement: .leading)
        let shown = hudPanels().filter { !before.contains(ObjectIdentifier($0)) }
        let panel = try #require(shown.first)
        let frame = panel.frame
        ThawHUD.dismiss()

        #expect(frame.minX == screen.frame.minX + ThawHUDPlacement.edgeInset)
        #expect(frame.width >= 120)
        #expect(frame.height >= 34)
        #expect(frame.maxY < screen.frame.maxY, "the capsule hangs below the bar")
        #expect(!panel.isVisible)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hasShadow)
    }

    @Test("A second capsule reuses the panel instead of stacking another")
    func reusesPanel() throws {
        let screen = try #require(NSScreen.screens.first)
        ThawHUD.dismiss()
        let before = Set(hudPanels().map(ObjectIdentifier.init))

        ThawHUD.show(symbol: "eye", text: "Hidden items shown", on: screen)
        ThawHUD.show(symbol: "eye.slash", text: "Hidden items hidden", on: screen, placement: .trailing)
        let shown = hudPanels().filter { !before.contains(ObjectIdentifier($0)) }
        let frame = shown.first?.frame
        ThawHUD.dismiss()

        #expect(shown.count == 1)
        if let frame {
            #expect(abs(frame.maxX - (screen.frame.maxX - ThawHUDPlacement.edgeInset)) < 0.5)
        }
        ThawHUD.dismiss()
        #expect(hudPanels().filter { !before.contains(ObjectIdentifier($0)) }.isEmpty, "dismissing twice is harmless")
    }
}
