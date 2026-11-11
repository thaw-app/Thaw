//
//  RevealedSectionSettleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A hidden section's first pictures after a reveal wait for its icons to finish sliding in.
@MainActor
@Suite("Revealed section settle", .serialized, .scratchDefaults)
struct RevealedSectionSettleTests {
    private typealias Cache = MenuBarItemImageCache

    private static func item(windowID: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.settle"), title: "Item", windowID: windowID, instanceIndex: 0),
            windowID: windowID, ownerPID: 501, sourcePID: 501,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22), title: "Item", isOnScreen: true
        )
    }

    @Test("The wait reads the bar until the icons hold still, on the frames read now, and skips items not on the bar")
    func settleReadsLiveFrames() async throws {
        let clock = TestClock()
        let settleClock = RevealCaptureSession.SettleClock(now: { clock.now }, sleep: { try? await clock.sleep(for: $0) })
        let parked = Self.item(windowID: 7, x: -2000)
        let live = Self.item(windowID: 9, x: 1000)
        let reader = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008]), strip: nil, items: [live])
        await Cache().settleRevealedSection([parked], appState: AppState(), reader: reader, clock: settleClock)
        #expect(await reader.captures.count == 3, "three matching reads, and it settles")

        let empty = try CaptureFixture(hosting: CaptureFixture.barCapture(opaque: false, glyphXs: [1008]), strip: nil)
        await Cache().settleRevealedSection([live], appState: AppState(), reader: empty, clock: settleClock)
        #expect(await empty.captures.isEmpty, "nothing on the bar to wait for")
    }

    @Test("A reflowing bar skips a pass, until enough were skipped in a row")
    func reflowSkipIsBounded() {
        #expect(Cache.skipsPassForReflow(reflowing: true, consecutiveSkips: 0))
        #expect(Cache.skipsPassForReflow(reflowing: true, consecutiveSkips: Cache.maximumReflowSkips - 1))
        #expect(Cache.skipsPassForReflow(reflowing: true, consecutiveSkips: Cache.maximumReflowSkips) == false)
        #expect(Cache.skipsPassForReflow(reflowing: false, consecutiveSkips: 0) == false)
    }

    @Test("A section just revealed waits; the visible section and later passes don't")
    func waitsOnlyRightAfterAReveal() {
        let now = ContinuousClock.now
        let justNow = now - .milliseconds(300)
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: .hidden, lastRevealChange: justNow, now: now))
        #expect(Cache.settlesRevealedPixels(for: .alwaysHidden, revealedSection: .alwaysHidden, lastRevealChange: justNow, now: now))
        #expect(Cache.settlesRevealedPixels(for: .visible, revealedSection: .hidden, lastRevealChange: justNow, now: now) == false)
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: nil, lastRevealChange: justNow, now: now) == false)
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: .hidden, lastRevealChange: nil, now: now) == false)
        let longAgo = now - Cache.revealedSettleWindow
        #expect(Cache.settlesRevealedPixels(for: .hidden, revealedSection: .hidden, lastRevealChange: longAgo, now: now) == false)
    }
}
