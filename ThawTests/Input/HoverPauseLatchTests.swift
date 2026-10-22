//
//  HoverPauseLatchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Hover pause after a press")
struct HoverPauseLatchTests {
    @Test("A press in empty space doesn't pause hover while the Hidden section is hidden")
    func pressWhileHidden() {
        #expect(!HoverPauseLatch.pausesOnEmptySpacePress(hiddenSectionIsRevealed: false))
    }

    @Test("A press in empty space pauses hover while the Hidden section is revealed")
    func pressWhileRevealed() {
        #expect(HoverPauseLatch.pausesOnEmptySpacePress(hiddenSectionIsRevealed: true))
    }

    @Test("Leaving the hover band ends the pause")
    func leavingReleases() {
        #expect(HoverPauseLatch.releasesOnPointerMove(
            isPaused: true,
            pointerIsInsideHoverBand: false,
            isZenModeActive: false
        ))
    }

    @Test("Moving within the hover band keeps the pause")
    func stayingKeepsPause() {
        #expect(!HoverPauseLatch.releasesOnPointerMove(
            isPaused: true,
            pointerIsInsideHoverBand: true,
            isZenModeActive: false
        ))
    }

    @Test("A pointer that never left keeps the pause until it does")
    func returnBeforeLeaving() {
        let moves = [true, true, true, false]
        let releases = moves.map {
            HoverPauseLatch.releasesOnPointerMove(isPaused: true, pointerIsInsideHoverBand: $0, isZenModeActive: false)
        }
        #expect(releases == [false, false, false, true])
    }

    @Test("Leaving the hover band doesn't end Zen Mode's lock")
    func zenKeepsLock() {
        #expect(!HoverPauseLatch.releasesOnPointerMove(
            isPaused: true,
            pointerIsInsideHoverBand: false,
            isZenModeActive: true
        ))
    }

    @Test("Nothing to release when hover isn't paused")
    func notPaused() {
        #expect(!HoverPauseLatch.releasesOnPointerMove(
            isPaused: false,
            pointerIsInsideHoverBand: false,
            isZenModeActive: false
        ))
    }
}
