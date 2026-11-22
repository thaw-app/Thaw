//
//  MenuOpenMonitorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

/// MenuOpenMonitor tells a real menu from a persistent menu-level window (an
/// untitled banner at layer 100) by tracking the previous probe's windows;
/// otherwise the rehide timer never converges. Drives the pure reconcile step.
@Suite("Menu open monitor persistence")
@MainActor
struct MenuOpenMonitorPersistenceTests {
    private func reconcile(
        _ currentIDs: Set<CGWindowID>,
        hasBaseline: inout Bool,
        priorCandidateWindowIDs: inout Set<CGWindowID>,
        openMenuWindowIDs: inout Set<CGWindowID>
    ) -> Bool {
        MenuOpenMonitor.reconcile(
            currentIDs: currentIDs,
            eligibleIDs: currentIDs,
            hasBaseline: &hasBaseline,
            priorCandidateWindowIDs: &priorCandidateWindowIDs,
            openMenuWindowIDs: &openMenuWindowIDs
        )
    }

    @Test("A persistent banner never counts as an open menu")
    func persistentBannerNeverCounts() {
        var hasBaseline = false
        var prior: Set<CGWindowID> = []
        var open: Set<CGWindowID> = []
        let banner: CGWindowID = 1

        // The banner is already on screen when probing starts.
        #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open.isEmpty)

        // It stays on screen across many polls and never counts.
        for _ in 0 ..< 5 {
            #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        }
        #expect(open.isEmpty)
    }

    @Test("A menu that opens after the baseline counts as open")
    func menuOpensAfterBaseline() {
        var hasBaseline = false
        var prior: Set<CGWindowID> = []
        var open: Set<CGWindowID> = []
        let banner: CGWindowID = 1
        let menu: CGWindowID = 2

        // Baseline with the banner already armed.
        #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))

        // A menu opens on top of the banner.
        #expect(reconcile([banner, menu], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open == [menu])
    }

    @Test("A menu held open across many polls keeps reading open")
    func menuStaysOpenAcrossPolls() {
        var hasBaseline = false
        var prior: Set<CGWindowID> = []
        var open: Set<CGWindowID> = []
        let banner: CGWindowID = 1
        let menu: CGWindowID = 2

        #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(reconcile([banner, menu], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))

        // The menu stays open for several 250 ms polls; it must keep reading
        // open, not just for the first tick.
        for _ in 0 ..< 5 {
            #expect(reconcile([banner, menu], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        }
        #expect(open == [menu])
    }

    @Test("Closing the menu clears the open state, then a reopen counts again")
    func menuCloseAndReopen() {
        var hasBaseline = false
        var prior: Set<CGWindowID> = []
        var open: Set<CGWindowID> = []
        let banner: CGWindowID = 1
        let menu: CGWindowID = 2

        #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(reconcile([banner, menu], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))

        // Menu closes.
        #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open.isEmpty)

        // A fresh open later is detected again.
        #expect(reconcile([banner, menu], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open == [menu])
    }

    @Test("Two distinct menus are tracked independently")
    func twoMenusTrackedIndependently() {
        var hasBaseline = false
        var prior: Set<CGWindowID> = []
        var open: Set<CGWindowID> = []
        let banner: CGWindowID = 1
        let menuA: CGWindowID = 2
        let menuB: CGWindowID = 3

        #expect(!reconcile([banner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(reconcile([banner, menuA], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(reconcile([banner, menuA, menuB], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open == [menuA, menuB])

        // menuA closes; menuB still open.
        #expect(reconcile([banner, menuB], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open == [menuB])
    }

    @Test("A banner that appears after the baseline counts while present")
    func bannerAppearingLaterCountsWhilePresent() {
        // Unknown panels that appear mid-session remain indistinguishable
        // from menus. Droppy's known overlay is excluded before reconciliation.
        var hasBaseline = false
        var prior: Set<CGWindowID> = []
        var open: Set<CGWindowID> = []
        let lateBanner: CGWindowID = 2

        #expect(!reconcile([], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(reconcile([lateBanner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open == [lateBanner])
        // It keeps counting while it persists.
        #expect(reconcile([lateBanner], hasBaseline: &hasBaseline, priorCandidateWindowIDs: &prior, openMenuWindowIDs: &open))
        #expect(open == [lateBanner])
    }
}

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

@Suite("Menu open monitor strip height")
struct MenuOpenMonitorStripTests {
    @Test("A bar that reserves room keeps that height", arguments: [24.0, 30.0, 38.0] as [CGFloat])
    func reservedHeight(reserved: CGFloat) {
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: reserved, measured: 12, hasMenuBar: true) == reserved)
    }

    @Test("An auto-hidden bar uses the measured height, and has no strip without one or without a menu bar")
    func autoHiddenBar() {
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: 30, hasMenuBar: true) == 30)
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: nil, hasMenuBar: true) == nil)
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: 0, hasMenuBar: true) == nil)
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: 30, hasMenuBar: false) == nil)
    }
}
