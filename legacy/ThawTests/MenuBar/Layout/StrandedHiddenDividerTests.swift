//
//  StrandedHiddenDividerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The parked-divider recovery's stranded test (#978).
///
/// A divider displaced past every item (minX -2742) never recovered because
/// "parked" was read off the leading edge alone, which every healthy collapsed
/// bar also fails since H_ctrl expands into an offscreen-reaching spacer. These
/// pin the both-edges check, on ``ParkedDividerLog``'s display geometry.
@Suite("Stranded hidden divider detection (#978)")
struct StrandedHiddenDividerTests {
    /// H_ctrl expanded into its spacer, reaching offscreen while its trailing edge
    /// stays beside visible. Counting it as parked would rebuild working dividers.
    @Test("A collapsed spacer reaching offscreen is not stranded")
    func collapsedSpacerIsNotStranded() {
        // Lengths.expanded = 10000; trailing edge inside the 2056-wide display.
        let expandedSpacer = ParkedDividerLog.bounds(minX: -8073, width: 10000)
        #expect(LayoutSolver.isFullyOffScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ) == false)

        // The leading-edge test flags this same frame, which is why the recovery dropped it.
        #expect(!LayoutSolver.isOnScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// A standard-length divider pushed left past its items, with no edge on any screen (#978).
    @Test("A divider displaced left past every item is stranded")
    func displacedLeftDividerIsStranded() {
        let stranded = ParkedDividerLog.bounds(minX: -2742)
        #expect(LayoutSolver.isFullyOffScreen(
            bounds: stranded,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// The mirror displacement: shoved rightward off the end of the bar.
    @Test("A divider displaced right off the bar is stranded")
    func displacedRightDividerIsStranded() {
        let stranded = ParkedDividerLog.bounds(minX: ParkedDividerLog.display.maxX + 44)
        #expect(LayoutSolver.isFullyOffScreen(
            bounds: stranded,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    @Test("An on-screen divider is not stranded")
    func onScreenDividerIsNotStranded() {
        let onScreen = ParkedDividerLog.bounds(minX: 1050)
        #expect(!LayoutSolver.isFullyOffScreen(
            bounds: onScreen,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// A sliver over the left screen edge still has an edge on a display; the drag
    /// machinery handles that case (#899).
    @Test("A half-visible divider is not stranded")
    func halfVisibleDividerIsNotStranded() {
        let sliver = ParkedDividerLog.bounds(minX: -34, width: 39)
        #expect(!LayoutSolver.isFullyOffScreen(
            bounds: sliver,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// With 36 to 40 items concealed and 1 to 5 visible, `shouldMoveHiddenDivider`
    /// stays false (#978). The fix goes through the rebuild recovery; flipping this
    /// would re-open #958's full-bar drags.
    @Test("Both sections populated keeps planning per-item moves")
    func populatedSectionsPlanPerItemMoves() {
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 40, liveVisibleCount: 1))
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 39, liveVisibleCount: 2))
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 36, liveVisibleCount: 5))
    }

    /// A collapsed always-hidden section puts AH_ctrl's leading edge far offscreen,
    /// so `.leftOfItem(AH_ctrl)` would click near minX -9189. The editor refuses the
    /// drag when leading-edge `isOnScreen` says offscreen (#923).
    @Test("A collapsed-section divider's leading edge reads offscreen for the editor drag guard")
    func collapsedDividerLeadingEdgeIsOffscreen() {
        // AH_ctrl at minX -9189 with the 10000-wide spacer, on the same 2056-wide display.
        let collapsedDivider = ParkedDividerLog.bounds(minX: -9189, width: 10000)
        #expect(!LayoutSolver.isOnScreen(
            bounds: collapsedDivider,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }
}

/// The AH_ctrl placement's anchor guard (#978, #980).
///
/// The AH_ctrl move anchored on `ControlItem.Hidden` while H_ctrl sat at -3596,
/// walked H_ctrl to -9322, and left the pair inverted with a zero-width hidden
/// section. Anchoring beside a parked item strands the dragged item.
///
/// The guard reads the leading edge, since the drop point derives from it.
@Suite("AH_ctrl placement anchor (#978)")
struct AlwaysHiddenPlacementAnchorTests {
    /// The stranded H_ctrl the AH_ctrl move anchored on in the follow-up log.
    @Test("#978's stranded H_ctrl is refused as an anchor")
    func strandedDividerIsRefusedAsAnchor() {
        #expect(!LayoutSolver.isOnScreen(
            bounds: ParkedDividerLog.bounds(minX: -3596),
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// Where that drag left H_ctrl; still refused, so the next cycle cannot walk it further.
    @Test("The post-drag position stays refused")
    func postDragPositionStaysRefused() {
        for minX in [-8612.0, -9322.0] as [CGFloat] {
            #expect(
                !LayoutSolver.isOnScreen(
                    bounds: ParkedDividerLog.bounds(minX: minX),
                    screenFrames: ParkedDividerLog.screenFrames
                ),
                "H_ctrl at minX=\(minX) must not be usable as a drag anchor"
            )
        }
    }

    /// The guard only refuses anchors visibly off the display.
    @Test("An on-screen anchor is still usable")
    func onScreenAnchorIsUsable() {
        #expect(LayoutSolver.isOnScreen(
            bounds: ParkedDividerLog.bounds(minX: 1050),
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// A collapsed H_ctrl's leading edge is far offscreen, so anchoring on it would
    /// still give an offscreen drop point. Refusing is intended; the per-item
    /// fallback places the items.
    @Test("A collapsed spacer is refused as an anchor too")
    func collapsedSpacerIsRefusedAsAnchor() {
        let expandedSpacer = ParkedDividerLog.bounds(minX: -8073, width: 10000)
        #expect(!LayoutSolver.isOnScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ))
        // Still not stranded, so the rebuild leaves it alone: different questions, one frame.
        #expect(!LayoutSolver.isFullyOffScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }
}
