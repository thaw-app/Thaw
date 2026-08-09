//
//  ParkedDividerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Log-replay lock for the #899 boundary-move storm.
///
/// #881 stopped `planHiddenDividerAnchor` from anchoring the `H_ctrl` drag to
/// a parked item. #899 is the same drag failing from the other side: the
/// anchor is back on the bar, so the anchor filter passes it, but the divider
/// itself is still parked and AppKit snaps it home on mouse-up. These tests
/// pin both halves against the shapes in ``ParkedDividerLog``, so the pair
/// cannot regress independently.
@Suite("Parked divider boundary move (#899)")
struct ParkedDividerTests {
    // MARK: - The half #881 already closed

    /// On the odd passes the anchor is parked, so no anchor is planned and no
    /// drag is attempted.
    @Test("A parked anchor plans no boundary move")
    func parkedAnchorPlansNothing() {
        let anchorBounds = ParkedDividerLog.bounds(
            minX: ParkedDividerLog.AnchorParked.anchorMinX
        )
        #expect(!LayoutSolver.isOnScreen(
            bounds: anchorBounds,
            screenFrames: ParkedDividerLog.screenFrames
        ))

        // The anchor is excluded from the candidate set, and it is the only
        // desired-hidden item live on the bar, so the planner returns nil.
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: [ParkedDividerLog.anchorUID],
            desiredVisible: [],
            liveMovableUIDs: []
        )
        #expect(anchor == nil)
    }

    // MARK: - The half #899 adds

    /// On the even passes the anchor is back on screen, so it survives the
    /// candidate filter and an anchor *is* planned. The anchor filter cannot
    /// prevent this drag.
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

    /// The divider the planned move would drag is parked, which is the
    /// condition the boundary move now checks before posting any events.
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

    /// The divider is parked on *both* states, so the guard covers the odd
    /// passes too — belt and braces with the anchor filter.
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

    /// The mismatch never reaches zero: the two states hand the same work
    /// back and forth, which is why nothing in the pass sequence itself ever
    /// stopped the storm.
    @Test("The logged pass sequence never converges")
    func loggedPassSequenceNeverConverges() {
        #expect(!ParkedDividerLog.mismatchPerPass.contains(0))
        #expect(Set(ParkedDividerLog.mismatchPerPass) == [5, 9])
    }

    /// The hidden section's membership is what alternates: the per-item pass
    /// evacuates it, the next pass puts it back.
    @Test("The hidden section alternates between populated and empty")
    func hiddenSectionAlternates() {
        #expect(ParkedDividerLog.hiddenWhenAnchorParked.count == 4)
        #expect(ParkedDividerLog.hiddenWhenAnchorOnScreen.isEmpty)
    }
}

/// The backoff that bounds the storm regardless of which state the bar is in.
///
/// The per-item LCS pass already consulted the failure ledger; the `H_ctrl`
/// boundary move did not, so a divider that could not land was re-dragged in
/// full by every re-sort. In #899 that ran for as long as the reporter left
/// the app running.
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

    /// A fresh divider is not under backoff, so the first attempt still runs.
    @Test("An unrecorded divider is not under backoff")
    func unrecordedDividerIsNotUnderBackoff() {
        let ledger = MenuBarItemFailureLedger()
        #expect(!ledger.isUnderBackoff(for: Self.divider()))
    }

    /// One recorded failure opens the window, so the next re-sort skips the
    /// drag instead of repeating it.
    @Test("A recorded failure puts the divider under backoff")
    func recordedFailurePutsDividerUnderBackoff() {
        let ledger = MenuBarItemFailureLedger()
        let divider = Self.divider()
        ledger.recordFailure(for: divider, kind: .other)
        #expect(ledger.isUnderBackoff(for: divider))
    }

    /// The item-taking overload has to agree with the key `recordFailure`
    /// writes under. Checking a different key than the ledger records is how
    /// a backoff silently never fires.
    @Test("The item overload reads the key recordFailure writes")
    func itemOverloadMatchesRecordedKey() {
        let ledger = MenuBarItemFailureLedger()
        let divider = Self.divider()
        ledger.recordFailure(for: divider, kind: .other)
        #expect(ledger.isUnderBackoff(key: divider.uniqueIdentifier))
        #expect(ledger.isUnderBackoff(for: divider))
    }

    /// A landed move clears the window so a divider that recovers is not left
    /// waiting out a backoff it no longer deserves.
    @Test("Success clears the backoff window")
    func successClearsBackoff() {
        let ledger = MenuBarItemFailureLedger()
        let divider = Self.divider()
        ledger.recordFailure(for: divider, kind: .other)
        ledger.recordSuccess(for: divider)
        #expect(!ledger.isUnderBackoff(for: divider))
    }
}
