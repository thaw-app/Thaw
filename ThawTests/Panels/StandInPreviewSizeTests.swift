//
//  StandInPreviewSizeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Stand-in preview size")
struct StandInPreviewSizeTests {
    private func item(_ bundleID: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", instanceIndex: 0),
            windowID: 1, ownerPID: 1, sourcePID: 1,
            bounds: CGRect(x: 0, y: 3, width: 32, height: 24), title: "Item-0", isOnScreen: true
        )
    }

    private let standIn = "\(ThawMenuBarIdentity.bundleIdentifier).extra.focus"

    @Test("Thaw's stand-ins are told apart from other apps")
    func recognizesStandIns() {
        #expect(ThawExtraGlyph.isStandIn(item(standIn).tag))
        #expect(!ThawExtraGlyph.isStandIn(item("com.example.app").tag))
        #expect(!ThawExtraGlyph.isStandIn(item("\(ThawMenuBarIdentity.bundleIdentifier).extra.unknown").tag),
                "an extra this build has no glyph for is not drawn as one")
    }

    @Test("A stand-in's symbol keeps its own size in the preview, while an app icon fills the tile")
    func standInKeepsItsSize() {
        let bounds = CGRect(x: 0, y: 0, width: 32, height: 24)
        let symbol = LayoutBarItemView.overflowFallbackDrawRect(for: item(standIn), imageSize: CGSize(width: 16, height: 15), bounds: bounds)
        #expect(symbol.size == CGSize(width: 16, height: 15))
        #expect(symbol.midX == bounds.midX && symbol.midY == bounds.midY)
        let appIcon = LayoutBarItemView.overflowFallbackDrawRect(for: item("com.example.app"), imageSize: CGSize(width: 16, height: 15), bounds: bounds)
        #expect(appIcon.size == CGSize(width: 24, height: 24))
    }
}
