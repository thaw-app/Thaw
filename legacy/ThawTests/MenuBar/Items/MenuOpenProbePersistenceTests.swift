//
//  MenuOpenProbePersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// A candidate menu window counts as open while young, or at any age while
/// the pointer is inside it. Persistent status-level windows (Droppy's shelf,
/// notch HUDs) used to match for their whole lifetime and defer every move (#879).
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

    // MARK: Display-sized overlays

    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func fullScreenCandidate(_ windowID: CGWindowID) -> MenuBarItemManager.MenuWindowCandidate {
        .init(windowID: windowID, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
    }

    /// A display-spanning drag-catcher overlay always contains the pointer, so
    /// the under-pointer rule held the probe open and deferred every drag (#899).
    @Test("A display-sized window is never a menu, young and under the pointer or not")
    func displaySizedWindowIsNeverAMenu() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [fullScreenCandidate(70)],
            pointerLocation: CGPoint(x: 700, y: 500),
            firstSeen: [:],
            now: start,
            isFirstProbe: false,
            threshold: threshold,
            displayBounds: [display]
        )
        #expect(!outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs == [70])
    }

    /// A genuine menu next to the overlay must still be seen through it.
    @Test("A fresh menu alongside a display-sized overlay still reports open")
    func freshMenuAlongsideOverlayReportsOpen() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [fullScreenCandidate(70), candidate(90, x: 200)],
            pointerLocation: nil,
            firstSeen: [:],
            now: start,
            isFirstProbe: false,
            threshold: threshold,
            displayBounds: [display]
        )
        #expect(outcome.isMenuOpen)
        #expect(outcome.ignoredPersistentWindowIDs == [70])
    }

    /// Without display geometry the size rule cannot fire; age and pointer decide.
    @Test("Without display bounds a large window follows the ordinary rules")
    func withoutDisplayBoundsSizeRuleCannotFire() {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: [fullScreenCandidate(70)],
            pointerLocation: nil,
            firstSeen: [:],
            now: start,
            isFirstProbe: false,
            threshold: threshold
        )
        #expect(outcome.isMenuOpen)
    }

    /// A zero-area window has no geometry to judge; age and pointer decide.
    @Test("An empty window is not display-sized")
    func emptyWindowIsNotDisplaySized() {
        #expect(
            !MenuBarItemManager.isDisplaySizedWindow(.zero, displayBounds: [display])
        )
    }

    @Test("Half the display's area is the boundary of the size rule")
    func halfDisplayAreaIsTheBoundary() {
        // Exactly half: an overlay.
        #expect(
            MenuBarItemManager.isDisplaySizedWindow(
                CGRect(x: 0, y: 0, width: 1512, height: 491),
                displayBounds: [display]
            )
        )
        // Just under half: menu-sized as far as this rule cares.
        #expect(
            !MenuBarItemManager.isDisplaySizedWindow(
                CGRect(x: 0, y: 0, width: 1512, height: 400),
                displayBounds: [display]
            )
        )
    }

    /// The area comparison is per display: a small-display-sized window on a much
    /// larger display is not an overlay there, and untouched displays have no say.
    @Test("The size rule only consults displays the window touches")
    func sizeRuleIsScopedToTouchedDisplays() {
        let smallDisplay = CGRect(x: 1512, y: 0, width: 800, height: 600)
        let windowOnLargeDisplay = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(
            !MenuBarItemManager.isDisplaySizedWindow(
                windowOnLargeDisplay,
                displayBounds: [display, smallDisplay]
            )
        )
        #expect(
            MenuBarItemManager.isDisplaySizedWindow(
                CGRect(x: 1512, y: 0, width: 800, height: 600),
                displayBounds: [display, smallDisplay]
            )
        )
    }
}
