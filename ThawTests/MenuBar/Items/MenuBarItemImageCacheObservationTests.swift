//
//  MenuBarItemImageCacheObservationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Observation
import os.lock
import Testing
@testable import Thaw

struct MenuBarItemImageCacheObservationTests {
    @Test
    @MainActor
    func trimmedImageLookupDoesNotPublishLRUBookkeeping() throws {
        let tag = MenuBarItemTag(
            namespace: .string("com.example.search-test"),
            title: "Search Test",
            windowID: 42
        )
        let image = try #require(makeOpaqueImage())
        let cache = MenuBarItemImageCache(images: [
            tag: .init(cgImage: image, scale: 1),
        ])
        let didPublishChange = OSAllocatedUnfairLock(initialState: false)

        withObservationTracking {
            #expect(cache.trimmedImage(for: tag) != nil)
        } onChange: {
            didPublishChange.withLock { $0 = true }
        }
        #expect(cache.trimmedImage(for: tag) != nil)

        #expect(
            !didPublishChange.withLock { $0 },
            "Reading a search-row image must not invalidate the row through LRU bookkeeping"
        )
    }

    @Test
    @MainActor
    func imageLookupMovesTagToMostRecentlyUsedPosition() throws {
        let olderTag = makeTag(title: "Older", windowID: 1)
        let recentTag = makeTag(title: "Recent", windowID: 2)
        let image = try #require(makeOpaqueImage())
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 1)
        let cache = MenuBarItemImageCache(images: [
            olderTag: captured,
            recentTag: captured,
        ])

        #expect(cache.image(for: recentTag) != nil)

        #expect(cache.leastRecentlyUsedTags(count: 1) == [olderTag])
        #expect(cache.lruEntryCount == 2)
    }

    @Test
    @MainActor
    func imageLookupSurvivesWindowIDChange() throws {
        let cachedTag = makeTag(title: "Stable", windowID: 1)
        let currentTag = makeTag(title: "Stable", windowID: 2)
        let image = try #require(makeOpaqueImage())
        let cache = MenuBarItemImageCache(images: [
            cachedTag: .init(cgImage: image, scale: 1),
        ])

        let result = cache.image(for: currentTag)

        #expect(result?.cgImage === image)
        #expect(result?.scale == 1)
    }

    @Test
    @MainActor
    func capturePermitSerializesOperations() async {
        let cache = MenuBarItemImageCache()
        let concurrency = OSAllocatedUnfairLock(initialState: (active: 0, maximum: 0))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 2 {
                group.addTask {
                    await cache.withCapturePermit {
                        concurrency.withLock {
                            $0.active += 1
                            $0.maximum = max($0.maximum, $0.active)
                        }
                        try? await Task.sleep(for: .milliseconds(20))
                        concurrency.withLock { $0.active -= 1 }
                    }
                }
            }
        }

        #expect(concurrency.withLock { $0.maximum } == 1)
    }

    private func makeTag(title: String, windowID: CGWindowID) -> MenuBarItemTag {
        MenuBarItemTag(
            namespace: .string("com.example.search-test"),
            title: title,
            windowID: windowID
        )
    }

    private func makeOpaqueImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        return context.makeImage()
    }
}
