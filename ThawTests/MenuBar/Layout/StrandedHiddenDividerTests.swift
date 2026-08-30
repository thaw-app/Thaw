//
//  StrandedHiddenDividerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The parked-divider recovery's stranded test (#978).
///
/// #978 is a divider displaced past every item — `minX=-2742.0` on a bar
/// whose owner kept arranging items — that never recovered, because the
/// recovery read "parked" off the leading edge alone. That test cannot
/// distinguish a stranded divider from a healthy collapsed one: hiding a
/// section expands H_ctrl into an offscreen-reaching spacer, so every
/// normal collapsed bar fails the leading-edge check. These tests pin the
/// both-edges semantics the recovery now uses, against the same display
/// geometry as ``ParkedDividerLog``.
@Suite("Stranded hidden divider detection (#978)")
struct StrandedHiddenDividerTests {
    /// A healthy collapsed bar: H_ctrl expanded into its spacer, frame
    /// reaching far offscreen to the left while the trailing edge stays
    /// anchored beside the visible section. This frame must NOT count as
    /// parked, or the recovery would rebuild dividers doing their job.
    @Test("A collapsed spacer reaching offscreen is not stranded")
    func collapsedSpacerIsNotStranded() {
        // Lengths.expanded = 10000; trailing edge inside the 2056-wide
        // display from ParkedDividerLog.
        let expandedSpacer = ParkedDividerLog.bounds(minX: -8073, width: 10000)
        #expect(LayoutSolver.isFullyOffScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ) == false)

        // Contrast: the leading-edge test flags this exact frame, which is
        // why the recovery had to move off it.
        #expect(!LayoutSolver.isOnScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// The #978 fault shape: a standard-length divider pushed left past all
    /// of its items, no edge on any screen. The recovery must see this.
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

    /// A divider sitting at its post beside the visible section.
    @Test("An on-screen divider is not stranded")
    func onScreenDividerIsNotStranded() {
        let onScreen = ParkedDividerLog.bounds(minX: 1050)
        #expect(!LayoutSolver.isFullyOffScreen(
            bounds: onScreen,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// A partially visible divider (sliver over the left screen edge) still
    /// has an edge on a display, so it does not qualify for a rebuild. The
    /// drag machinery owns that case through its own checks (#899).
    @Test("A half-visible divider is not stranded")
    func halfVisibleDividerIsNotStranded() {
        let sliver = ParkedDividerLog.bounds(minX: -34, width: 39)
        #expect(!LayoutSolver.isFullyOffScreen(
            bounds: sliver,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// #978's decisive observation: with 36–40 items concealed and 1–5
    /// visible, `shouldMoveHiddenDivider` stays false, so neither repair
    /// direction ran while the divider sat stranded. Pinning the false here
    /// documents that the fix routes through the rebuild recovery, not
    /// through flipping this predicate — flipping it would re-open #958's
    /// full-bar drags.
    @Test("Both sections populated keeps planning per-item moves")
    func populatedSectionsPlanPerItemMoves() {
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 40, liveVisibleCount: 1))
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 39, liveVisibleCount: 2))
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 36, liveVisibleCount: 5))
    }

    /// The Layout editor drag guard (#923). A collapsed always-hidden section
    /// expands AH_ctrl into a spacer whose leading edge sits far offscreen,
    /// so `.leftOfItem(AH_ctrl)` would target a click point around minX -9189.
    /// The editor refuses the drag when `isOnScreen` (leading-edge) reads the
    /// divider as offscreen. This pins that detection against the #923 log's
    /// geometry, separate from the both-edges stranded test the recovery uses.
    @Test("A collapsed-section divider's leading edge reads offscreen for the editor drag guard")
    func collapsedDividerLeadingEdgeIsOffscreen() {
        // AH_ctrl at minX=-9189 with the 10000-wide concealment spacer, on
        // the same 2056-wide display as ParkedDividerLog.
        let collapsedDivider = ParkedDividerLog.bounds(minX: -9189, width: 10000)
        #expect(!LayoutSolver.isOnScreen(
            bounds: collapsedDivider,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }
}

/// The AH_ctrl placement's anchor guard (#978, #980).
///
/// #978's second, worse fault came in through the always-hidden placement,
/// not the visible/hidden boundary repair: the AH_ctrl move anchored on
/// `ControlItem.Hidden` while H_ctrl sat at `minX=-3596`, the drag walked
/// H_ctrl to `-9322`, and the pair came out inverted with the hidden section
/// reading zero width. Anchoring a drag beside a parked item is what strands
/// the item being dragged, which is the same reasoning the Thaw-icon
/// relocation guard already carried.
///
/// The guard reads the leading edge, not both edges. A drag anchor is
/// exactly the case ``LayoutSolver/isOnScreen(bounds:screenFrames:)`` is the
/// right test for: the drop point is derived from the anchor's edge, so an
/// anchor whose leading edge is offscreen gives a drop point that is too.
@Suite("AH_ctrl placement anchor (#978)")
struct AlwaysHiddenPlacementAnchorTests {
    /// The stranded H_ctrl from the follow-up log's 19:44:22 cycle, the one
    /// the AH_ctrl move anchored on.
    @Test("#978's stranded H_ctrl is refused as an anchor")
    func strandedDividerIsRefusedAsAnchor() {
        #expect(!LayoutSolver.isOnScreen(
            bounds: ParkedDividerLog.bounds(minX: -3596),
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// Where that drag left H_ctrl. Still refused, so the next cycle cannot
    /// walk it further.
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

    /// An ordinary hidden item anchor on the bar still passes: the guard
    /// only refuses anchors it can see are off the display, so the common
    /// placement is untouched.
    @Test("An on-screen anchor is still usable")
    func onScreenAnchorIsUsable() {
        #expect(LayoutSolver.isOnScreen(
            bounds: ParkedDividerLog.bounds(minX: 1050),
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }

    /// A healthy collapsed H_ctrl expands into a spacer whose leading edge
    /// is far offscreen. Anchoring AH_ctrl on it would still derive an
    /// offscreen drop point, so the leading-edge test refusing here is the
    /// intended behaviour, not a false positive — the per-item fallback
    /// places the items instead.
    @Test("A collapsed spacer is refused as an anchor too")
    func collapsedSpacerIsRefusedAsAnchor() {
        let expandedSpacer = ParkedDividerLog.bounds(minX: -8073, width: 10000)
        #expect(!LayoutSolver.isOnScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ))
        // ...and is still not *stranded*, so the divider rebuild leaves it
        // alone. The two tests answer different questions about one frame.
        #expect(!LayoutSolver.isFullyOffScreen(
            bounds: expandedSpacer,
            screenFrames: ParkedDividerLog.screenFrames
        ))
    }
}
