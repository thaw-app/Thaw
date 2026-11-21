//
//  EmptyPassInventoryRefreshTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A visible pass that captured nothing asks for an inventory scan only when it asked for pictures.
@MainActor
@Suite("Empty pass inventory refresh")
struct EmptyPassInventoryRefreshTests {
    private typealias Pass = MenuBarItemImageCache.CapturePass

    @Test("A visible pass that asked for pictures and got none suggests a stale inventory")
    func failedVisiblePass() {
        #expect(Pass().suggestsStaleInventory(in: .visible))
    }

    @Test("A visible pass that asked for none, as with app icons on in Layout, doesn't")
    func nothingRequested() {
        #expect(!Pass.nothingRequested.suggestsStaleInventory(in: .visible))
    }

    @Test("A hidden section's empty pass doesn't, as before")
    func hiddenSection() {
        #expect(!Pass().suggestsStaleInventory(in: .hidden))
    }

    @Test("A pass with a picture doesn't")
    func capturedSomething() throws {
        var pass = Pass()
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        pass.captured[MenuBarItemTag(namespace: .string("com.example.a"), title: "Item-0")] =
            try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
        #expect(!pass.suggestsStaleInventory(in: .visible))
    }
}
