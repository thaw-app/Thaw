//
//  MenuOpenProbePersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Tests for the pure persistence classification behind
/// `isAnyMenuBarItemMenuOpen()` (#879 regression): a candidate menu window
/// counts as an open menu while it is young, or at any age while the
/// pointer is inside it. Persistent status-level windows (Droppy's shelf,
/// notch HUDs) previously matched the probe for the app's whole lifetime
/// and deferred every move indefinitely.
@Suite("Menu open probe persistence classification")
struct MenuOpenProbePersistenceTests {
    private let threshold = MenuBarItemManager.menuWindowPersistenceThreshold
    private let start = ContinuousClock.now

    private func candidate(_ windowID: CGWindowID, x: CGFloat = 0) -> MenuBarItemManager.MenuWindowCandidate {
        .init(windowID: windowID, bounds: CGRect(x: x, y: 0, width: 100, height: 100))
    }

    @Test("No candidates means no open menu")
    func noCandidates() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [],
            pointerLocation: nil,
            firstSeen: [:],
            now: start,
            isFirstProbe: true,
            threshold: threshold
        )
        #expect(!outcome.isMenuOpen)
        #expect(outcome.updatedFirstSeen.isEmpty)
    }

    @Test("Windows present at the first probe are grandfathered as persistent")
    func firstProbeGrandfathers() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(50)],
            pointerLocation: nil,
            firstSeen: [:],
            now: start,
            isFirstProbe: true,
            threshold: threshold
        )
        #expect(!outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs == [50])
    }

    @Test("A window appearing after the first probe is a fresh menu")
    func freshWindowIsMenu() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(60)],
            pointerLocation: nil,
            firstSeen: [:],
            now: start,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs.isEmpty)
        #expect(outcome.updatedFirstSeen[60] == start)
    }

    @Test("A tracked window becomes persistent once it outlives the threshold")
    func trackedWindowAges() {
        let firstSeen: [CGWindowID: ContinuousClock.Instant] = [60: start]

        let young = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(60)],
            pointerLocation: nil,
            firstSeen: firstSeen,
            now: start + threshold - .seconds(1),
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(young.isMenuOpen)

        let old = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(60)],
            pointerLocation: nil,
            firstSeen: firstSeen,
            now: start + threshold,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(!old.isMenuOpen)
        #expect(old.ignoredPersistentWindowIDs == [60])
    }

    @Test("A persistent window under the pointer still counts as an open menu")
    func persistentWindowUnderPointerDefers() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(60)],
            pointerLocation: CGPoint(x: 50, y: 50),
            firstSeen: [60: start - threshold],
            now: start,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs.isEmpty)
    }

    @Test("A persistent window with the pointer elsewhere is ignored")
    func persistentWindowPointerOutsideIgnored() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(60)],
            pointerLocation: CGPoint(x: 500, y: 500),
            firstSeen: [60: start - threshold],
            now: start,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(!outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs == [60])
    }

    @Test("Entries for windows that disappeared are pruned so reused IDs start fresh")
    func prunesClosedWindows() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(70)],
            pointerLocation: nil,
            firstSeen: [60: start - threshold, 70: start],
            now: start,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(outcome.updatedFirstSeen[60] == nil)
        #expect(outcome.updatedFirstSeen[70] == start)
    }

    @Test("A fresh menu alongside a persistent window still reports open")
    func freshAndPersistentMix() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [candidate(50), candidate(90, x: 200)],
            pointerLocation: nil,
            firstSeen: [50: start - threshold],
            now: start,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs == [50])
    }
}
