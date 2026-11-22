//
//  CapturePassTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A capture refused because no Thaw surface is open is not a failed read")
struct RefusedCaptureTests {
    private let items = ["A", "B"].map {
        ItemsFixture.item($0, bundle: "com.example.status", x: 1000, y: 4.5, windowID: 101, ownerPID: 999_991, sourcePID: 999_991)
    }

    @Test("A refused capture leaves the cached pictures alone")
    func refusedCaptureInvalidatesNothing() {
        var pass = MenuBarItemImageCache.CapturePass()

        let recorded = pass.noteMissingCapture(of: items, captureWasAllowed: false)

        #expect(!recorded)
        #expect(pass.unreadable.isEmpty)
        #expect(pass.invalidatedTags.isEmpty)
    }

    @Test("A capture that was allowed and still returned nothing is a failure")
    func failedCaptureInvalidates() {
        var pass = MenuBarItemImageCache.CapturePass()

        let recorded = pass.noteMissingCapture(of: items, captureWasAllowed: true)

        #expect(recorded)
        #expect(pass.unreadable.count == 2)
        #expect(pass.invalidatedTags == Set(items.map(\.tag)))
    }
}

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

    @Test("A hidden section's empty pass doesn't")
    func hiddenSection() {
        #expect(!Pass().suggestsStaleInventory(in: .hidden))
    }

    @Test("A pass with a picture doesn't")
    func capturedSomething() throws {
        var pass = Pass()
        pass.captured[MenuBarItemTag(namespace: .string("com.example.a"), title: "Item-0")] =
            try ItemsFixture.glyph(width: 2, height: 2, color: nil)
        #expect(!pass.suggestsStaleInventory(in: .visible))
    }
}
