//
//  MenuBarDisplayCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

struct MenuBarDisplayCacheTests {
    private let oldFrame = CGRect(x: 2560, y: 290, width: 500, height: 34)

    @Test("Rearranging connected displays drops app-menu frames and heights")
    func rearrangementInvalidatesGeometry() {
        var cache = MenuBarDisplayCache()
        cache.applicationDidChange(to: 7)
        cache.storeMenuFrame(oldFrame, for: 2, generation: cache.generation)
        cache.storeHeight(34, for: 2, generation: cache.generation)
        cache.removeDisconnectedDisplays(keeping: [1, 2])
        #expect(cache.menuFrames[2] == oldFrame)
        #expect(cache.menuBarHeights[2] == 34)
        cache.geometryDidChange()
        cache.applicationDidChange(to: 7)
        #expect(cache.menuFrames.isEmpty)
        #expect(cache.menuBarHeights.isEmpty)
        let newFrame = CGRect(x: -1710, y: 290, width: 500, height: 34)
        cache.storeMenuFrame(newFrame, for: 2, generation: cache.generation)
        #expect(cache.menuFrames[2] == newFrame)
    }

    @Test("Reads started before a topology or menu-owner change cannot repopulate the cache")
    func staleReadsAreRejected() {
        var cache = MenuBarDisplayCache()
        let oldGeneration = cache.generation
        cache.geometryDidChange()
        cache.storeMenuFrame(oldFrame, for: 2, generation: oldGeneration)
        let stored = cache.storeHeight(34, for: 2, generation: oldGeneration)
        #expect(!stored)
        #expect(cache.menuFrames.isEmpty)
        #expect(cache.menuBarHeights.isEmpty)
        let beforeAppChange = cache.generation
        cache.applicationDidChange(to: 8)
        cache.storeMenuFrame(oldFrame, for: 2, generation: beforeAppChange)
        #expect(cache.menuFrames.isEmpty)
        cache.storeMenuFrame(oldFrame, for: 2, generation: cache.generation)
        cache.storeHeight(34, for: 2, generation: cache.generation)
        cache.removeDisconnectedDisplays(keeping: [1])
        #expect(cache.menuFrames.isEmpty)
        #expect(cache.menuBarHeights.isEmpty)
    }
}
