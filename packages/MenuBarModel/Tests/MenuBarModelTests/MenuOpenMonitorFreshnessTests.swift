//
//  MenuOpenMonitorFreshnessTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

/// A fresh check reads the windows after it is asked, so a menu opened a moment ago counts.
@Suite("Menu open monitor freshness")
@MainActor
struct MenuOpenMonitorFreshnessTests {
    private static let owner: pid_t = 123_456

    @MainActor
    private final class Scene {
        var windows: [WindowInfo] = []
        /// While true, a probe reads the windows and then waits for release().
        var holdsProbes = false
        private var heldProbes: [CheckedContinuation<Void, Never>] = []

        var hasHeldProbe: Bool {
            !heldProbes.isEmpty
        }

        func monitor(cacheFreshness: Duration = .zero) -> MenuOpenMonitor {
            MenuOpenMonitor(
                onScreenItems: { [MenuOpenMonitorFreshnessTests.item] },
                cacheFreshness: cacheFreshness,
                windowSnapshot: { await self.snapshot() },
                menuBarStrips: { [CGRect(x: 0, y: 0, width: 3000, height: 24)] }
            )
        }

        private func snapshot() async -> [WindowInfo] {
            let read = windows
            if holdsProbes {
                await withCheckedContinuation { heldProbes.append($0) }
            }
            return read
        }

        func release() {
            holdsProbes = false
            heldProbes.forEach { $0.resume() }
            heldProbes = []
        }
    }

    private static let item = MenuBarItem(
        tag: MenuBarItemTag(namespace: .null, title: "menu-owner"),
        windowID: 900,
        ownerPID: owner,
        sourcePID: owner,
        bounds: CGRect(x: 1400, y: 0, width: 24, height: 24),
        title: "menu-owner",
        isOnScreen: true
    )

    /// A menu hanging from the bar, owned by the item's app.
    private static let menu = WindowInfo(windowID: 2, ownerPID: owner, bounds: CGRect(x: 973, y: 0, width: 1062, height: 334), layer: 100, title: "")

    @Test("A fresh check sees a menu that opened after the cached answer")
    func freshCheckSkipsTheCache() async {
        let scene = Scene()
        let monitor = scene.monitor(cacheFreshness: .seconds(60))
        #expect(await monitor.isAnyMenuOpen() == false)

        scene.windows = [Self.menu]
        #expect(await monitor.isMenuOpen(ownedBy: [Self.owner]) == false, "the cached answer")
        #expect(await monitor.isMenuOpen(ownedBy: [Self.owner], fresh: true))
        #expect(await monitor.isAnyMenuOpen(), "the fresh answer replaces the cached one")
    }

    @Test("A fresh check doesn't take the answer of a probe that read the windows before it was asked")
    func freshCheckDoesNotJoinAnEarlierProbe() async {
        let scene = Scene()
        let monitor = scene.monitor()
        #expect(await monitor.isAnyMenuOpen() == false)

        scene.holdsProbes = true
        let early = Task { await monitor.isAnyMenuOpen() }
        while !scene.hasHeldProbe {
            await Task.yield()
        }
        scene.windows = [Self.menu]
        let fresh = Task { await monitor.isMenuOpen(ownedBy: [Self.owner], fresh: true) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        scene.release()

        #expect(await early.value == false, "read before the menu opened")
        #expect(await fresh.value)
    }
}
