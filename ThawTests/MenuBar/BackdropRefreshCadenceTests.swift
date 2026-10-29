//
//  BackdropRefreshCadenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Backdrop refresh cadence")
struct BackdropRefreshCadenceTests {
    @Test("Fast while a cover is likely, slow otherwise")
    func fastAndSlow() {
        #expect(BackdropRefreshCadence.nextInterval(coverLikely: true, barVisible: true, screenLocked: false, idleSeconds: 1) == BackdropRefreshCadence.fast)
        #expect(BackdropRefreshCadence.nextInterval(coverLikely: false, barVisible: true, screenLocked: false, idleSeconds: 1) == BackdropRefreshCadence.slow)
    }

    @Test("Paused while the screen is locked or nobody has touched the Mac for a while")
    func paused() {
        #expect(BackdropRefreshCadence.nextInterval(coverLikely: true, barVisible: true, screenLocked: true, idleSeconds: 1) == nil)
        #expect(BackdropRefreshCadence.nextInterval(coverLikely: true, barVisible: true, screenLocked: false, idleSeconds: BackdropRefreshCadence.idleThreshold) == nil)
    }

    @Test("Paused while no display shows the bar, whatever else is true")
    func pausedWithoutABar() {
        #expect(BackdropRefreshCadence.nextInterval(coverLikely: true, barVisible: false, screenLocked: false, idleSeconds: 1) == nil)
        #expect(BackdropRefreshCadence.nextInterval(coverLikely: false, barVisible: false, screenLocked: false, idleSeconds: 1) == nil)
    }

    @Test("Only the fast cadence forces a re-composite; the slow one waits for the windows to change")
    func forcing() {
        #expect(BackdropRefreshCadence.forcesRecomposite(coverLikely: true))
        #expect(!BackdropRefreshCadence.forcesRecomposite(coverLikely: false))
    }

    @Test("A window that moves under the bar changes the key, and so do the same windows stacked in another order")
    func keyFollowsWindowPlaces() {
        let rect = CGRect(x: 0, y: 0, width: 1920, height: 30)
        let before = MenuBarBackdrop.stripKey(rect: rect, windows: [(7, CGRect(x: 0, y: 0, width: 400, height: 300)), (3, .zero)])
        let reordered = MenuBarBackdrop.stripKey(rect: rect, windows: [(3, .zero), (7, CGRect(x: 0, y: 0, width: 400, height: 300))])
        let moved = MenuBarBackdrop.stripKey(rect: rect, windows: [(7, CGRect(x: 200, y: 0, width: 400, height: 300)), (3, .zero)])
        #expect(before != reordered)
        #expect(before != moved)
        #expect(before == MenuBarBackdrop.stripKey(rect: rect, windows: [(7, CGRect(x: 0, y: 0, width: 400, height: 300)), (3, .zero)]))
    }

    @Test("Only on-screen windows below the ceiling that touch the rect are composited")
    func windowsBelowTheBar() async {
        let everywhere = CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)
        let below = await MenuBarBackdrop.windowsBelowMenuBar(intersecting: everywhere)
        #expect(below.allSatisfy { $0.bounds.intersects(everywhere) })
        #expect(Set(below.map(\.id)).count == below.count)
        #expect(await MenuBarBackdrop.windowsBelowMenuBar(intersecting: everywhere, belowLayer: Int.min).isEmpty)
        #expect(await MenuBarBackdrop.windowsBelowMenuBar(intersecting: CGRect(x: -900_000, y: -900_000, width: 1, height: 1)).isEmpty)
    }

    @Test("A one-off read under no window composites nothing")
    @MainActor
    func captureNothing() async {
        let image = await MenuBarBackdrop().capture(CGRect(x: 0, y: 0, width: 10, height: 10), belowLayer: Int.min)
        #expect(image == nil)
    }
}
