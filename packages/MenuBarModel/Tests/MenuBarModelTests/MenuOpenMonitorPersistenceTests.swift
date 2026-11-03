//
//  MenuOpenMonitorPersistenceTests.swift
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
