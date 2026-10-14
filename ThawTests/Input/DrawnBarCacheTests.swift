//
//  DrawnBarCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

/// A click must find a drawn-bar answer without the pointer having moved, and
/// never one taken before the bar last changed.
@MainActor
@Suite("Drawn bar cache")
struct DrawnBarCacheTests {
    private let bar = [MenuBarAgentWindow.Entry(ownerPID: 7, frame: CGRect(x: 1300, y: 0, width: 38, height: 30))]

    private func answer(from cache: MenuBarPointerAXCache) async -> [MenuBarAgentWindow.Entry]? {
        for _ in 0 ..< 100 {
            if let answer = cache.drawnBarAnswer() { return answer.entries }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    @Test("A change reads the bar again, with no pointer movement")
    func changeReadsTheBar() async {
        let bar = bar
        let cache = MenuBarPointerAXCache(readDrawnBar: { bar })
        cache.drawnBarDidChange()
        #expect(await answer(from: cache) == bar)
    }

    @Test("An answer from before the last change is not used")
    func olderAnswerIsDropped() async {
        let bar = bar
        let cache = MenuBarPointerAXCache(readDrawnBar: { bar })
        cache.drawnBarDidChange()
        _ = await answer(from: cache)
        cache.drawnBarDidChange()
        #expect(cache.drawnBarAnswer() == nil)
        #expect(await answer(from: cache) == bar)
    }

    @Test("A bar that cannot be read leaves no answer")
    func unreadableBar() async {
        let cache = MenuBarPointerAXCache(readDrawnBar: { nil })
        cache.drawnBarDidChange()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(cache.drawnBarAnswer() == nil)
    }
}
