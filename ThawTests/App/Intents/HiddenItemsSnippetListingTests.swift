//
//  HiddenItemsSnippetListingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// The rows the hidden items snippet lists, built from an AppState that was never set up.
@MainActor
@Suite("Hidden items snippet listing", .serialized, .scratchDefaults)
struct HiddenItemsSnippetListingTests {
    private typealias World = LayoutEditorWorld

    /// An item owned by a process that isn't running, so no app icon stands in for a missing capture.
    private func item(_ title: String) -> MenuBarItem {
        World.item(MenuBarItemTag(namespace: .string("com.example.snippet.\(title)"), title: title, instanceIndex: 0), ownerPID: 999_997)
    }

    private func capture(width: Int) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: 18,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 18))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
    }

    /// The alpha at the middle of glyph drawn into a 40 by 18 point box: a solid capture fills it, the outline fallback symbol leaves it clear.
    private func centerAlpha(of glyph: Image?) throws -> CGFloat {
        let renderer = try ImageRenderer(content: #require(glyph).frame(width: 40, height: 18))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)).alphaComponent
    }

    @Test("Only the first twelve hidden items get a row, and the rest are counted")
    func rowLimit() {
        let world = World()
        let items = (1 ... 14).map { item("Item\($0)") }
        world.seat(items, in: .hidden)
        world.seat([item("Shown")], in: .visible)

        let listing = HiddenMenuBarItemsSnippet.listing(in: world.appState)

        #expect(listing.rows.map(\.id) == items.prefix(12).map(\.uniqueIdentifier))
        #expect(listing.rows.map(\.name) == items.prefix(12).map { MenuBarItemDisplayName.displayName(for: $0) })
        #expect(listing.overflowCount == 2)
    }

    @Test("A captured item shows its capture at its own width, kept within the row budget, and an item without one its fallback")
    func capturedGlyphs() throws {
        let world = World()
        let medium = item("Medium")
        let wide = item("Wide")
        let bare = item("Bare")
        world.seat([medium, wide, bare], in: .hidden)
        try world.appState.imageCache.setCapture(capture(width: 40), for: medium.tag)
        try world.appState.imageCache.setCapture(capture(width: 200), for: wide.tag)

        // Bare's owner isn't running, so it falls back to the outline menubar.rectangle symbol.
        let fallback = try #require(OverflowFallbackIcon.preferredImage(for: bare, appState: world.appState))
        let symbol = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: MenuBarItemDisplayName.displayName(for: bare))
        #expect(fallback.tiffRepresentation == symbol?.tiffRepresentation, "An app icon would fill the middle")
        let rows = HiddenMenuBarItemsSnippet.listing(in: world.appState).rows

        #expect(try rows.map { try centerAlpha(of: $0.glyph) } == [1, 1, 0])
        #expect(rows.map(\.glyphWidth) == [40, 60, 18])
    }
}
