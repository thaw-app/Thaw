//
//  MenuBarItemImageCacheMemoryPressureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// A memory warning drops the least recently used half of the cache, but not the pictures of
/// hidden items: only a reveal can take those again, and the Thaw Bar shows them (#1606).
@MainActor
@Suite("Memory pressure", .serialized, .scratchDefaults)
struct MenuBarItemImageCacheMemoryPressureTests {
    private typealias Cache = MenuBarItemImageCache

    private static func tag(_ bundleID: String, windowID: CGWindowID? = nil) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", windowID: windowID)
    }

    private static func capture() throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: 20, height: 16, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 16))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
    }

    /// A cache holding tags in order of use, the first least recently used.
    private static func cache(holding tags: [MenuBarItemTag]) throws -> Cache {
        let cache = Cache(screenIsLocked: { false })
        for tag in tags {
            try cache.setCapture(capture(), for: tag)
            cache.updateAccessOrder(for: tag)
        }
        return cache
    }

    @Test("Without hidden items, the least recently used half goes")
    func dropsLeastRecentlyUsedHalf() throws {
        let tags = (0 ..< 4).map { Self.tag("com.example.\($0)", windowID: CGWindowID($0 + 1)) }
        let cache = try Self.cache(holding: tags)

        cache.handleMemoryPressure(concealedTags: [])

        #expect(Set(cache.capturesByTag.keys) == Set(tags.suffix(2)))
    }

    @Test("A hidden item's picture stays even when it was used least recently")
    func keepsHiddenItemPictures() throws {
        // Loaded from disk, so filed without the window ID the live item has.
        let hiddenFromDisk = Self.tag("com.example.hidden")
        let hiddenLive = Self.tag("com.example.hidden", windowID: 9)
        let visible = (0 ..< 3).map { Self.tag("com.example.\($0)", windowID: CGWindowID($0 + 1)) }
        let cache = try Self.cache(holding: [hiddenFromDisk] + visible)

        cache.handleMemoryPressure(concealedTags: [hiddenLive])

        #expect(cache.capturesByTag[hiddenFromDisk] != nil)
        #expect(Set(cache.capturesByTag.keys) == [hiddenFromDisk, visible[2]])
    }

    @Test("When every picture is a hidden item's, none goes")
    func keepsAllWhenAllHidden() throws {
        let tags = (0 ..< 3).map { Self.tag("com.example.\($0)", windowID: CGWindowID($0 + 1)) }
        let cache = try Self.cache(holding: tags)

        cache.handleMemoryPressure(concealedTags: tags)

        #expect(Set(cache.capturesByTag.keys) == Set(tags))
    }
}
