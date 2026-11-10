//
//  MenuBarItemImageCacheIdleTrimTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Verifies that idle trim flushes captures to disk, purges all in-memory
/// CGImages (including concealed items), and re-hydrates lazily from disk.
@MainActor
@Suite("Idle trim full purge and disk hydration", .serialized, .scratchDefaults, .timeLimit(.minutes(1)))
struct MenuBarItemImageCacheIdleTrimTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: ScratchDefaults.name("MenuBarItemImageCacheIdleTrimTests"), directoryHint: .isDirectory)

    private static func tag(_ bundleID: String, _ title: String, windowID: CGWindowID? = nil) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundleID), title: title, windowID: windowID)
    }

    private static func capture() throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: 24,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 24 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 20))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }

    @Test("trimForIdle flushes to disk and purges all in-memory captures when no consumer is visible")
    func trimFlushesAndPurgesEverything() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MenuBarItemImageCacheDiskStore(cachesDirectory: directory)
        let cache = MenuBarItemImageCache(diskStore: store)
        let appState = AppState()
        cache.appState = appState
        cache.hasLoadedFromDisk = true

        let visibleTag = Self.tag("com.example.visible", "V", windowID: 1)
        let hiddenTag = Self.tag("com.example.hidden", "H", windowID: 2)
        try cache.setCapture(Self.capture(), for: visibleTag)
        try cache.setCapture(Self.capture(), for: hiddenTag)
        cache.updateAccessOrder(for: visibleTag)
        cache.updateAccessOrder(for: hiddenTag)

        #expect(cache.cacheSize == 2)
        #expect(cache.lruEntryCount == 2)

        await cache.trimForIdle()

        #expect(cache.cacheSize == 0)
        #expect(cache.lruEntryCount == 0)
        #expect(!cache.hasLoadedFromDisk)

        // Disk store holds the flushed captures for lazy hydration on reveal.
        let file = try #require(store.readSaveFile())
        #expect(file.entries[visibleTag.tagIdentifier] != nil)
        #expect(file.entries[hiddenTag.tagIdentifier] != nil)

        // Opening a consumer hydrates entries back into RAM lazily.
        await cache.ensureDiskLoaded()
        #expect(cache.hasLoadedFromDisk)
        #expect(cache.cacheSize == 2)
    }

    @Test("trimForIdle skips purge while an image consumer is visible")
    func trimAbortsWhenConsumerActive() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MenuBarItemImageCacheDiskStore(cachesDirectory: directory)
        let cache = MenuBarItemImageCache(diskStore: store)
        let appState = AppState()
        appState.navigationState.isThawBarPresented = true
        cache.appState = appState

        let tag = Self.tag("com.example.active", "A", windowID: 10)
        try cache.setCapture(Self.capture(), for: tag)

        await cache.trimForIdle()

        #expect(cache.cacheSize == 1)
        #expect(cache.image(for: tag) != nil)
    }
}
