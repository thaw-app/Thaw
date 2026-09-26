//
//  ParkedDividerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Replays the #899 boundary-move storm against ``ParkedDividerLog``.
///
/// #881 stopped anchoring the `H_ctrl` drag to a parked item. #899 fails from
/// the other side: the anchor is back on the bar, but the divider is still
/// parked and AppKit snaps it home on mouse-up. Both halves are pinned here.
@Suite("Parked divider boundary move (#899)")
struct ParkedDividerTests {
    // MARK: - The half #881 already closed

    /// On odd passes the anchor is parked, so no drag is attempted.
    @Test("A parked anchor plans no boundary move")
    func parkedAnchorPlansNothing() {
        let anchorBounds = ParkedDividerLog.bounds(
            minX: ParkedDividerLog.AnchorParked.anchorMinX
        )
        #expect(!LayoutSolver.isOnScreen(
            bounds: anchorBounds,
            screenFrames: ParkedDividerLog.screenFrames
        ))

        // The anchor is the only desired-hidden item live and it is excluded, so nil.
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: [ParkedDividerLog.anchorUID],
            desiredVisible: [],
            liveMovableUIDs: []
        )
        #expect(anchor == nil)
    }

    // MARK: - The half #899 adds

    /// On even passes the anchor is on screen, so the anchor filter cannot prevent the drag.
    @Test("An on-screen anchor still plans a boundary move")
    func onScreenAnchorStillPlansAMove() {
        let anchorBounds = ParkedDividerLog.bounds(
            minX: ParkedDividerLog.AnchorOnScreen.anchorMinX
        )
        #expect(LayoutSolver.isOnScreen(
            bounds: anchorBounds,
            screenFrames: ParkedDividerLog.screenFrames
        ))

        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: [ParkedDividerLog.anchorUID],
            desiredVisible: [],
            liveMovableUIDs: [ParkedDividerLog.anchorUID]
        )
        #expect(anchor == .rightOf(ParkedDividerLog.anchorUID))
    }

    /// The boundary move now checks for a parked divider before posting events.
    @Test("The divider is parked on the pass whose anchor is on screen")
    func dividerIsParkedWhenAnchorIsOnScreen() {
        let dividerBounds = ParkedDividerLog.bounds(
            minX: ParkedDividerLog.AnchorOnScreen.hiddenDividerMinX
        )
        #expect(!LayoutSolver.isOnScreen(
            bounds: dividerBounds,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// Parked in both states, so the guard also backs up the anchor filter on odd passes.
    @Test("The divider is parked on both alternating states")
    func dividerIsParkedOnBothStates() {
        for minX in [
            ParkedDividerLog.AnchorParked.hiddenDividerMinX,
            ParkedDividerLog.AnchorOnScreen.hiddenDividerMinX,
        ] {
            #expect(!LayoutSolver.isOnScreen(
                bounds: ParkedDividerLog.bounds(minX: minX),
                screenFrames: ParkedDividerLog.screenFrames
            ))
        }
    }

    // MARK: - The loop the log recorded

    /// The two states hand the same work back and forth, so the passes alone never stop the storm.
    @Test("The logged pass sequence never converges")
    func loggedPassSequenceNeverConverges() {
        #expect(!ParkedDividerLog.mismatchPerPass.contains(0))
        #expect(Set(ParkedDividerLog.mismatchPerPass) == [5, 9])
    }

    /// The per-item pass empties hidden and the next pass refills it.
    @Test("The hidden section alternates between populated and empty")
    func hiddenSectionAlternates() {
        #expect(ParkedDividerLog.hiddenWhenAnchorParked.count == 4)
        #expect(ParkedDividerLog.hiddenWhenAnchorOnScreen.isEmpty)
    }
}

/// The backoff that bounds the storm in either state.
///
/// The `H_ctrl` boundary move did not consult the failure ledger, so a divider
/// that could not land was re-dragged by every re-sort for as long as the app ran (#899).
@MainActor
@Suite("Boundary move backoff (#899)", .serialized)
struct BoundaryMoveBackoffTests {
    private static func divider() -> MenuBarItem {
        MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .string("com.stonerl.Thaw"),
                title: "Thaw.ControlItem.Hidden"
            ),
            windowID: 27481,
            bounds: ParkedDividerLog.bounds(
                minX: ParkedDividerLog.AnchorOnScreen.hiddenDividerMinX
            )
        )
    }

    @Test("An unrecorded divider is not under backoff")
    func unrecordedDividerIsNotUnderBackoff() {
        let ledger = MenuBarItemFailureLedger()
        #expect(!ledger.isUnderBackoff(for: Self.divider()))
    }

    /// One failure opens the window, so the next re-sort skips the drag.
    @Test("A recorded failure puts the divider under backoff")
    func recordedFailurePutsDividerUnderBackoff() {
        let ledger = MenuBarItemFailureLedger()
        let divider = Self.divider()
        ledger.recordFailure(for: divider, kind: .other)
        #expect(ledger.isUnderBackoff(for: divider))
    }

    /// Checking a different key than `recordFailure` writes is how a backoff silently never fires.
    @Test("The item overload reads the key recordFailure writes")
    func itemOverloadMatchesRecordedKey() {
        let ledger = MenuBarItemFailureLedger()
        let divider = Self.divider()
        ledger.recordFailure(for: divider, kind: .other)
        #expect(ledger.isUnderBackoff(key: divider.uniqueIdentifier))
        #expect(ledger.isUnderBackoff(for: divider))
    }

    /// A divider that recovers must not wait out a backoff it no longer deserves.
    @Test("Success clears the backoff window")
    func successClearsBackoff() {
        let ledger = MenuBarItemFailureLedger()
        let divider = Self.divider()
        ledger.recordFailure(for: divider, kind: .other)
        ledger.recordSuccess(for: divider)
        #expect(!ledger.isUnderBackoff(for: divider))
    }
}
