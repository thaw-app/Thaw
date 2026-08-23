//
//  HiddenDividerBoundaryTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers the hidden-divider boundary check that applyProfileLayout's
/// Phase 1 runs before the always-hidden divider placement.
///
/// The boundary check exists because neither of the two mechanisms that
/// preceded it can see a divider that has drifted past every managed item:
///
/// - Phase 1's `crossSectionMoves` / `totalSectionMismatch` tallies both
///   intersect against the currently-occupied hidden and always-hidden
///   sets, so a bar where both are empty scores zero on both.
/// - The LCS pass receives sequences with the dividers stripped, so a
///   divergence that is purely a divider position leaves current equal to
///   desired and plans no moves.
///
/// Together those produced #879: every hidden item classified visible, and
/// the apply reported "all items already in correct positions".
@Suite("Hidden divider boundary")
struct HiddenDividerBoundaryTests {
    // MARK: - Mismatch counting

    /// A bar that already matches the profile scores zero, so the divider
    /// move never runs on a healthy layout.
    @Test("A layout that matches the profile reports no boundary mismatch")
    func matchingLayoutReportsNoMismatch() {
        let mismatch = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: ["a", "b"],
            currentHidden: ["c"],
            currentAlwaysHidden: ["d"],
            desiredVisible: ["a", "b"],
            desiredHidden: ["c"],
            desiredAlwaysHidden: ["d"]
        )

        #expect(mismatch == 0)
    }

    /// An item the profile assigns to hidden but that currently classifies
    /// visible is on the wrong side of the divider and must be counted.
    @Test("An item that should be hidden but reads visible counts")
    func itemThatShouldBeHiddenCounts() {
        let mismatch = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: ["a", "b"],
            currentHidden: [],
            currentAlwaysHidden: [],
            desiredVisible: ["a"],
            desiredHidden: ["b"],
            desiredAlwaysHidden: []
        )

        #expect(mismatch == 1)
    }

    /// The reverse direction counts too: the divider can drift the other
    /// way and swallow items the profile wants visible.
    @Test("An item that should be visible but reads hidden counts")
    func itemThatShouldBeVisibleCounts() {
        let mismatch = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: [],
            currentHidden: ["a", "b"],
            currentAlwaysHidden: [],
            desiredVisible: ["a"],
            desiredHidden: ["b"],
            desiredAlwaysHidden: []
        )

        #expect(mismatch == 1)
    }

    /// Always-hidden counts as concealed for this check. Which of the two
    /// concealed sections an item lands in is the always-hidden divider's
    /// problem, handled by the AH_ctrl planning that follows; the hidden
    /// divider only decides concealed versus visible.
    @Test("Hidden and always-hidden are one side for this check")
    func hiddenAndAlwaysHiddenCountAsOneSide() {
        // Every item is concealed, and every item is meant to be
        // concealed — they are merely in the wrong concealed section.
        let mismatch = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: [],
            currentHidden: ["a"],
            currentAlwaysHidden: ["b"],
            desiredVisible: [],
            desiredHidden: ["b"],
            desiredAlwaysHidden: ["a"]
        )

        #expect(mismatch == 0,
                "a hidden↔always-hidden swap is the AH_ctrl planner's job, not the hidden divider's")
    }

    /// Items the profile does not mention are unmanaged arrivals routed by
    /// planUnmanagedPlacement, so they must not drag the divider.
    @Test("An item absent from the profile does not count")
    func unmanagedItemDoesNotCount() {
        let mismatch = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: ["a", "newcomer"],
            currentHidden: [],
            currentAlwaysHidden: [],
            desiredVisible: ["a"],
            desiredHidden: [],
            desiredAlwaysHidden: []
        )

        #expect(mismatch == 0)
    }

    // MARK: - Anchor planning

    /// Section order runs right-to-left, so index 0 of the hidden section
    /// is its rightmost item and the divider belongs immediately right of
    /// it — the gap between the hidden and visible groups.
    @Test("The anchor is the rightmost live hidden item")
    func anchorsToRightmostHiddenItem() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["h1", "h2", "h3"],
            desiredVisible: ["v1", "v2"],
            liveMovableUIDs: ["h1", "h2", "h3", "v1", "v2"]
        )

        #expect(anchor == .rightOf("h1"))
    }

    /// A profile lists items that are not running right now. The anchor
    /// has to be an item actually on the bar, so the planner walks inward
    /// from the rightmost until it finds one.
    @Test("A hidden item that is not running is skipped as an anchor")
    func skipsHiddenItemsThatAreNotLive() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["notRunning", "h2", "h3"],
            desiredVisible: ["v1"],
            liveMovableUIDs: ["h2", "h3", "v1"]
        )

        #expect(anchor == .rightOf("h2"))
    }

    /// With nothing live on the hidden side the divider still has to end
    /// up left of every visible item, so it anchors to the leftmost one —
    /// the last entry in the visible order.
    @Test("An empty hidden side anchors left of the leftmost visible item")
    func fallsBackToLeftmostVisibleItem() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["notRunning"],
            desiredVisible: ["v1", "v2", "v3"],
            liveMovableUIDs: ["v1", "v2", "v3"]
        )

        #expect(anchor == .leftOf("v3"))
    }

    /// Nothing live on either side leaves no anchor to drag against; the
    /// caller logs and falls through to the LCS pass rather than guessing.
    @Test("No live item on either side yields no anchor")
    func noLiveItemYieldsNoAnchor() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["h1"],
            desiredVisible: ["v1"],
            liveMovableUIDs: []
        )

        #expect(anchor == nil)
    }

    // MARK: - Field replay (#879)

    /// Replays the Phase 1 sets captured in the #879 field log, where the
    /// reporter's hidden section emptied into visible after upgrading from
    /// 2.0.0-rc.1 to rc.2 and could not be restored.
    ///
    /// The log's own numbers were `crossSectionMoves=0`,
    /// `totalSectionMismatch=0`, verdict "all items already in correct
    /// positions" — with 29 items in `desiredHidden` and none in
    /// `currentHidden`.
    @Suite("Issue 879 field log")
    struct Issue879FieldLog {
        /// The 28 items the log reported in the visible section, in the
        /// order it reported them (index 0 rightmost).
        static let currentVisible = [
            "com.stonerl.Thaw:Thaw.ControlItem.Visible",
            "com.robinlu.mac.Tooth-Fairy:Item-0",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.network",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.cpu",
            "app.updatest.Updatest:Item-0",
            "com.techsmith.snagit.capturehelper:Item-0",
            "com.1password.1password:bb3cc23c-6950-4e96-8b40-850e09f46934",
            "com.rogueamoeba.soundsource:SSMainAppMenuIcon",
            "85C27NK92C.com.flexibits.fantastical2.mac.helper:Fantastical",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.time",
            "com.apphousekitchen.aldente-pro:Item-0",
            "de.kuatsu.consul:Item-0",
            "pro.betterdisplay.BetterDisplay:Item-0",
            "com.malwarebytes.mbam.frontend.agent:Item-0",
            "com.onmyway133.PastePal:Item-0",
            "com.microsoft.OneDrive-mac:Item-0",
            "86Z3GCJ4MF.com.noodlesoft.HazelHelper:Item-0",
            "org.amnezia.awg:Item-0",
            "com.elgato.StreamDeck:Item-0",
            "com.DigiDNA.iMazing2Mac.Mini:Item-0",
            "net.ericmann.parachute:Item-0",
            "io.robbie.HomeAssistant:Item-0",
            "com.apple.controlcenter:WiFi",
            "com.apple.controlcenter:Bluetooth",
            "com.purevpn.app.mac:Item-0",
            "com.valerijs.boguckis.gumroad.TextSniper:Item-0",
            "com.econtechnologies.backgrounder.chronosync:Item-0",
            "com.raycast.macos:extension_auto-quit-app_auto-quit-app-menubar__e77dadf4-2dd6-4fd8-9041-d67068b934ae",
        ]

        /// The profile's hidden section as the log printed it. The Phase 1
        /// lines log sorted sets, so this is membership only — tests that
        /// depend on section *order* use synthetic fixtures instead.
        static let desiredHidden: Set<String> = [
            "86Z3GCJ4MF.com.noodlesoft.HazelHelper:Item-0",
            "app.loshadki.OpenIn.v4:Item-0",
            "com.DigiDNA.iMazing2Mac.Mini:Item-0",
            "com.Tweaking4all.ConnectMeNow4:Item-0",
            "com.apphousekitchen.aldente-pro:Item-0",
            "com.apple.controlcenter:Bluetooth",
            "com.apple.controlcenter:WiFi",
            "com.econtechnologies.backgrounder.chronosync:Item-0",
            "com.elgato.StreamDeck:Item-0",
            "com.expandrive.ExpanDrive:Item-0",
            "com.logi.cp-dev-mgr:Item-0",
            "com.malwarebytes.mbam.frontend.agent:Item-0",
            "com.microsoft.OneDrive-mac:Item-0",
            "com.onmyway133.PastePal:Item-0",
            "com.openai.codex:Item-0",
            "com.pdfeditor.pdfeditormac:Item-0",
            "com.purevpn.app.mac:Item-0",
            "com.raycast.macos:extension_auto-quit-app_auto-quit-app-menubar__e77dadf4-2dd6-4fd8-9041-d67068b934ae",
            "com.tweety.MediaMate:Item-1",
            "com.valerijs.boguckis.gumroad.TextSniper:Item-0",
            "de.kuatsu.consul:Item-0",
            "io.getpurge.app:Item-0",
            "io.robbie.HomeAssistant:Item-0",
            "net.ericmann.parachute:Item-0",
            "nz.co.pixeleyes.AutoMounter:Item-0",
            "org.amnezia.awg:Item-0",
            "org.mozilla.firefox:Item-0",
            "org.mozilla.firefox:Item-1",
            "pro.betterdisplay.BetterDisplay:Item-0",
        ]

        /// The profile's visible section as the log printed it.
        static let desiredVisible: Set<String> = [
            "85C27NK92C.com.flexibits.fantastical2.mac.helper:Fantastical",
            "app.updatest.Updatest:Item-0",
            "com.1password.1password:bb3cc23c-6950-4e96-8b40-850e09f46934",
            "com.apple.controlcenter:BentoBox-0",
            "com.apple.controlcenter:Clock",
            "com.apple.controlcenter:FocusModes",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.cpu",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.network",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.time",
            "com.robinlu.mac.Tooth-Fairy:Item-0",
            "com.rogueamoeba.soundsource:SSMainAppMenuIcon",
            "com.stonerl.Thaw:Thaw.ControlItem.Visible",
            "com.techsmith.snagit.capturehelper:Item-0",
        ]

        /// Every item on the bar belongs to exactly one of the profile's two
        /// sections, and the bar's order already groups them: the 10 items
        /// bound for visible occupy the rightmost 10 slots and the 18 bound
        /// for hidden occupy the rest. Nothing is interleaved and nothing is
        /// unmanaged. The layout is not scrambled — only the divider is in
        /// the wrong place.
        @Test("The bar is cleanly partitioned; only the divider is misplaced")
        func barIsCleanlyPartitioned() {
            let boundVisible = Self.currentVisible.filter(Self.desiredVisible.contains)
            let boundHidden = Self.currentVisible.filter(Self.desiredHidden.contains)

            #expect(boundVisible.count == 10)
            #expect(boundHidden.count == 18)
            #expect(boundVisible + boundHidden == Self.currentVisible,
                    "the bar is already grouped visible-then-hidden, so only H_ctrl sits in the wrong gap")
        }

        /// The LCS pass is handed sequences with the dividers stripped. The
        /// bar's grouping means those two sequences are identical, so the
        /// planner returns no moves — reproducing the log's "all items
        /// already in correct positions" verdict.
        ///
        /// This is a characterization test, not a regression: the fix does
        /// not change what the LCS sees. It pins the blindness the boundary
        /// check exists to compensate for.
        @Test("The LCS pass plans no moves, as the field log reported")
        func lcsPlansNoMoves() {
            let desiredNoControls = Self.currentVisible.filter(Self.desiredVisible.contains)
                + Self.currentVisible.filter(Self.desiredHidden.contains)

            var sectionMap = [String: String]()
            for uid in Self.desiredVisible {
                sectionMap[uid] = "visible"
            }
            for uid in Self.desiredHidden {
                sectionMap[uid] = "hidden"
            }

            let moves = LayoutSolver.planLCSMoveSequence(
                currentNoControls: Self.currentVisible,
                desiredNoControls: desiredNoControls,
                sectionMap: sectionMap
            )

            #expect(moves.isEmpty,
                    "with the dividers stripped the two sequences coincide, so the LCS sees nothing to do")
        }

        /// The boundary check does see it: 18 items the profile assigns to
        /// hidden are classifying visible. That non-zero count is what makes
        /// Phase 1 drag H_ctrl instead of concluding the bar is correct.
        @Test("The boundary check counts all 18 items stranded in visible")
        func boundaryCheckCountsStrandedItems() {
            let mismatch = LayoutSolver.hiddenBoundaryMismatch(
                currentVisible: Set(Self.currentVisible),
                currentHidden: [],
                currentAlwaysHidden: [],
                desiredVisible: Self.desiredVisible,
                desiredHidden: Self.desiredHidden,
                desiredAlwaysHidden: []
            )

            #expect(mismatch == 18)
        }

        /// The reporter had no always-hidden section, so `ahCtrlUID` was nil
        /// and Phase 1's existing repair branch — which is bound on that
        /// optional — could not have run even had its tallies been non-zero.
        /// The boundary move must not carry the same gate.
        @Test("The boundary is repairable without an always-hidden divider")
        func repairDoesNotDependOnAlwaysHiddenDivider() {
            let live = Set(Self.currentVisible)
            let anchor = LayoutSolver.planHiddenDividerAnchor(
                // Profile order for the hidden section, reconstructed from the
                // bar: the 18 stranded items in the order they sit on it.
                desiredHidden: Self.currentVisible.filter(Self.desiredHidden.contains),
                desiredVisible: Self.currentVisible.filter(Self.desiredVisible.contains),
                liveMovableUIDs: live
            )

            #expect(anchor == .rightOf("com.apphousekitchen.aldente-pro:Item-0"),
                    "H_ctrl belongs immediately right of the rightmost hidden item")
        }
    }
}

/// Pins the refusal that keeps the H_ctrl boundary move off Thaw's own
/// chevron (#958).
///
/// The candidate set the caller hands the planner is already filtered to
/// items that are movable and on screen. Thaw's control items pass both on
/// every pass, so on a bar where the profile's items have been dragged to
/// the wrong side of the divider and parked there, the chevron is the only
/// candidate left standing — and it is the one anchor that must not be
/// used. Dragging H_ctrl up to it sweeps the section it was restoring
/// across with it.
///
/// #958's reporter imported a known-good plist with Thaw quit, confirmed it
/// live, and watched the first apply after relaunch undo it:
///
/// ```
/// Profile layout Phase 1: hiddenBoundaryMismatch=11
/// Profile layout: 11 item(s) on the wrong side of H_ctrl, moving H_ctrl to the boundary
/// Profile layout: moving H_ctrl -> left of <com.stonerl.Thaw:Thaw.ControlItem.Visible>
/// post-H_ctrl classification crossSectionMoves=0, totalSectionMismatch=0
/// ```
///
/// The roster below is the visible order from the `broken_profile.json`
/// attached to the same issue, in profile order — index 0 rightmost. The
/// chevron sits at index 11 with four items to its left, none of which are
/// movable, which is what leaves it as the last candidate the search finds.
@Suite("Boundary anchor refuses Thaw's own items")
struct BoundaryAnchorControlItemRefusalTests {
    private static let chevron = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
    private static let hiddenDivider = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"

    private static let desiredVisible = [
        "leits.MeetingBar:Item-0",
        "com.steipete.codexbar:codexbar-codex",
        "com.steipete.codexbar:codexbar-claude",
        "com.tunabellysoftware.tgpro:Item-0",
        "eu.exelban.Stats:CPU_bar_chart",
        "eu.exelban.Stats:GPU_bar_chart",
        "eu.exelban.Stats:RAM_bar_chart",
        "com.rogueamoeba.soundsource:SSMainAppMenuIcon",
        "com.rogueamoeba.soundsource:Input",
        "com.apphousekitchen.aldente-pro:Item-0",
        "eu.exelban.Stats:Network_speed",
        chevron,
        "org.p0deje.Maccy:Item-0",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:BentoBox-0",
        "com.apple.controlcenter:Clock",
    ]

    private static let desiredHidden = [
        "com.electron.dockerdesktop:Item-0",
        "com.proxyman.NSProxy:Item-0",
        "com.apple.controlcenter:WiFi",
    ]

    // MARK: - The refusal

    /// The reporter's state: every hidden-side item parked off screen and
    /// every real visible item dragged across with them, leaving the
    /// chevron alone in the candidate set.
    @Test("The chevron alone yields no anchor")
    func chevronAloneYieldsNoAnchor() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron],
            unanchorableUIDs: [Self.chevron, Self.hiddenDivider]
        )

        #expect(anchor == nil)
    }

    /// The behaviour the refusal replaces, so the regression is pinned by
    /// the shape it used to take rather than only by its absence.
    @Test("Without the bar, the same inputs anchor on the chevron")
    func sameInputsUsedToAnchorOnTheChevron() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron]
        )

        #expect(anchor == .leftOf(Self.chevron))
    }

    /// Refusing means stopping, not searching on. The next candidate to the
    /// chevron's right is an item the profile wants right of the divider,
    /// so anchoring there would drag H_ctrl past it and conceal it — the
    /// same collapse one item smaller.
    @Test("The search does not continue past a refused anchor")
    func searchDoesNotContinuePastARefusedAnchor() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: [],
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron, "eu.exelban.Stats:Network_speed"],
            unanchorableUIDs: [Self.chevron]
        )

        #expect(anchor == nil)
    }

    /// A divider that reached the desired-hidden order is refused the same
    /// way, from the other side.
    @Test("A control item on the hidden side is refused too")
    func controlItemOnTheHiddenSideIsRefused() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: [Self.chevron, "com.proxyman.NSProxy:Item-0"],
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron, "com.proxyman.NSProxy:Item-0"],
            unanchorableUIDs: [Self.chevron]
        )

        #expect(anchor == nil)
    }

    // MARK: - What the refusal must not cost

    /// A real item at the boundary is still an anchor. The refusal is not a
    /// blanket stand-down on bars that happen to have the chevron live.
    @Test("A live real item to the chevron's left still anchors the move")
    func liveRealItemStillAnchorsTheMove() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron, "org.p0deje.Maccy:Item-0"],
            unanchorableUIDs: [Self.chevron, Self.hiddenDivider]
        )

        #expect(anchor == .leftOf("org.p0deje.Maccy:Item-0"))
    }

    /// The hidden side is tried first and is unaffected, so the common
    /// repair — a profile whose hidden items are back on the bar — plans
    /// the same move it always did.
    @Test("A live hidden item still wins over the visible fallback")
    func liveHiddenItemStillWins() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: ["com.proxyman.NSProxy:Item-0", Self.chevron],
            unanchorableUIDs: [Self.chevron, Self.hiddenDivider]
        )

        #expect(anchor == .rightOf("com.proxyman.NSProxy:Item-0"))
    }

    // MARK: - Telling the two nil cases apart in the log

    /// A refusal names the item it refused, so a field log distinguishes
    /// "the items are on the wrong side" from "the items are not running".
    @Test("The candidate helper names the refused chevron")
    func candidateHelperNamesTheRefusedChevron() {
        let candidate = LayoutSolver.hiddenDividerAnchorCandidate(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron]
        )

        #expect(candidate == Self.chevron)
    }

    /// A bar with nothing live reports no candidate at all, which is the
    /// pre-existing nil and keeps its own log line.
    @Test("Nothing live yields no candidate")
    func nothingLiveYieldsNoCandidate() {
        let candidate = LayoutSolver.hiddenDividerAnchorCandidate(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: []
        )

        #expect(candidate == nil)
    }
}

/// Pins which of the two boundary repairs Phase 1 takes.
///
/// Dragging H_ctrl re-sections every item it crosses, so it is the cheap
/// repair only when the divider itself is what drifted. #958 is the case
/// where it was not: one item on the wrong side, nine still correctly
/// concealed, and the drag planned to reach that one item would have carried
/// the divider from minX -3871 to 1648, across the entire visible section.
@Suite("Divider drag versus per-item boundary moves")
struct HiddenBoundaryRepairChoiceTests {
    @Test("Nothing concealed means the divider drifted past everything (#879)")
    func emptyConcealedSideDragsTheDivider() {
        // The bar the boundary check was written for: eighteen managed items,
        // all of them reading visible, none behind the divider.
        #expect(LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 0, liveVisibleCount: 18))
    }

    @Test("Nothing visible is the collapsed bar, and the drag is the recovery (#958)")
    func emptyVisibleSideDragsTheDivider() {
        #expect(LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 19, liveVisibleCount: 0))
    }

    @Test("One stray item with a populated hidden section moves the item (#958)")
    func oneStrayItemMovesTheItem() {
        // oa's 21 August reading: nine items correctly concealed, one on the
        // wrong side. The divider is where it belongs.
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 9, liveVisibleCount: 17))
    }

    @Test("A bar with most items concealed still moves items, not the divider")
    func mostlyConcealedBarMovesItems() {
        // oa's 05:00 reading: thirty-two concealed, eleven of them wrongly so.
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 32, liveVisibleCount: 4))
    }

    @Test("An empty bar qualifies for the drag rather than deadlocking")
    func emptyBarDragsTheDivider() {
        #expect(LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 0, liveVisibleCount: 0))
    }
}

/// The repair has to move the same items the check counted.
@Suite("Boundary offenders agree with the boundary tally")
struct HiddenBoundaryOffenderTests {
    private func offenders(
        currentVisible: Set<String>,
        currentHidden: Set<String>,
        currentAlwaysHidden: Set<String> = [],
        desiredVisible: Set<String>,
        desiredHidden: Set<String>,
        desiredAlwaysHidden: Set<String> = [],
        overflowExemptUIDs: Set<String> = []
    ) -> LayoutSolver.HiddenBoundaryOffenders {
        let split = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: currentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: currentAlwaysHidden,
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: desiredAlwaysHidden,
            overflowExemptUIDs: overflowExemptUIDs
        )
        // The tally is defined in terms of the split, and every case here
        // checks that the two cannot drift apart.
        #expect(split.count == LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: currentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: currentAlwaysHidden,
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: desiredAlwaysHidden,
            overflowExemptUIDs: overflowExemptUIDs
        ))
        return split
    }

    @Test("A matching layout has no offenders")
    func matchingLayoutHasNoOffenders() {
        let split = offenders(
            currentVisible: ["a", "b"],
            currentHidden: ["c"],
            desiredVisible: ["a", "b"],
            desiredHidden: ["c"]
        )
        #expect(split.wronglyVisible.isEmpty)
        #expect(split.wronglyConcealed.isEmpty)
        #expect(split.count == 0)
    }

    @Test("An item that should be concealed is named on the visible side")
    func strayVisibleItemIsNamed() {
        let split = offenders(
            currentVisible: ["a", "b", "c"],
            currentHidden: [],
            desiredVisible: ["a", "b"],
            desiredHidden: ["c"]
        )
        #expect(split.wronglyVisible == ["c"])
        #expect(split.wronglyConcealed.isEmpty)
    }

    @Test("An item that should be visible is named on the concealed side")
    func strayConcealedItemIsNamed() {
        let split = offenders(
            currentVisible: ["a"],
            currentHidden: ["b", "c"],
            desiredVisible: ["a", "b"],
            desiredHidden: ["c"]
        )
        #expect(split.wronglyVisible.isEmpty)
        #expect(split.wronglyConcealed == ["b"])
    }

    @Test("Always-hidden counts as the concealed side, not a third direction")
    func alwaysHiddenIsPartOfTheConcealedSide() {
        let split = offenders(
            currentVisible: ["a"],
            currentHidden: [],
            currentAlwaysHidden: ["b"],
            desiredVisible: ["a", "b"],
            desiredHidden: [],
            desiredAlwaysHidden: []
        )
        #expect(split.wronglyConcealed == ["b"])
        // An item moving between hidden and always-hidden is AH_ctrl's
        // problem and must not show up here.
        let acrossAH = offenders(
            currentVisible: ["a"],
            currentHidden: ["b"],
            desiredVisible: ["a"],
            desiredHidden: [],
            desiredAlwaysHidden: ["b"]
        )
        #expect(acrossAH.count == 0)
    }

    @Test("Offenders travel in both directions at once")
    func bothDirectionsAtOnce() {
        let split = offenders(
            currentVisible: ["a", "c"],
            currentHidden: ["b", "d"],
            desiredVisible: ["a", "b"],
            desiredHidden: ["c", "d"]
        )
        #expect(split.wronglyVisible == ["c"])
        #expect(split.wronglyConcealed == ["b"])
        #expect(split.count == 2)
    }

    @Test("An item the profile does not manage is nobody's offender")
    func unmanagedItemIsNotAnOffender() {
        let split = offenders(
            currentVisible: ["a", "stranger"],
            currentHidden: [],
            desiredVisible: ["a"],
            desiredHidden: []
        )
        #expect(split.count == 0)
    }

    // MARK: - Notch-overflow exemption (#958)

    /// An item ejected into hidden by the notch-overflow rebalance sits on
    /// the concealed side while the profile still lists it visible. That
    /// divergence is by design; counting it makes Phase 1 recall the item
    /// to visible, and the next cycle's overflow plan ejects it again — a
    /// two-drag oscillation for as long as the bar stays over budget.
    /// The exemption must absorb exactly that case.
    @Test("A notch-overflow-ejected item sitting in hidden is exempt from the boundary check")
    func overflowEjectedItemInHiddenIsExempt() {
        let split = offenders(
            currentVisible: ["a", "b"],
            currentHidden: ["c", "ejected"],
            desiredVisible: ["a", "b", "ejected"],
            desiredHidden: ["c"],
            desiredAlwaysHidden: [],
            overflowExemptUIDs: ["ejected"]
        )
        #expect(split.isEmpty)

        // Without the exemption the same bar counts the ejected item —
        // this documents the oscillation mechanism, not desired behavior.
        let unexempt = offenders(
            currentVisible: ["a", "b"],
            currentHidden: ["c", "ejected"],
            desiredVisible: ["a", "b", "ejected"],
            desiredHidden: ["c"]
        )
        #expect(unexempt.wronglyConcealed == ["ejected"])
    }

    /// An ejected item that drifted into always-hidden has left the section
    /// the eject placed it in. That is genuine drift and must keep counting,
    /// matching the rule `currentLayoutDivergesFromSaved` applies.
    @Test("A notch-overflow-ejected item that drifted to always-hidden still counts")
    func overflowEjectedItemInAlwaysHiddenStillCounts() {
        let split = offenders(
            currentVisible: ["a", "b"],
            currentHidden: ["c"],
            currentAlwaysHidden: ["ejected"],
            desiredVisible: ["a", "b", "ejected"],
            desiredHidden: ["c"],
            desiredAlwaysHidden: [],
            overflowExemptUIDs: ["ejected"]
        )
        #expect(split.wronglyConcealed == ["ejected"])
    }

    /// An ejected item that made its own way back to the visible side needs
    /// no exemption (it is where the profile wants it), but the exempt set
    /// must not swallow other genuine offenders on the concealed side.
    @Test("The exemption does not hide unrelated wrongly-concealed items")
    func exemptionDoesNotHideOtherOffenders() {
        let split = offenders(
            currentVisible: ["a", "b"],
            currentHidden: ["c", "drifted", "ejected"],
            desiredVisible: ["a", "b", "drifted", "ejected"],
            desiredHidden: ["c"],
            desiredAlwaysHidden: [],
            overflowExemptUIDs: ["ejected"]
        )
        #expect(split.wronglyConcealed == ["drifted"])
    }

    /// The exemption exists to stop Phase 1 recalling ejected items from
    /// hidden. An exempt UID currently sitting VISIBLE and wanted concealed
    /// is the opposite situation — a genuine offender in the other direction
    /// — and must keep counting whatever the exempt set says.
    @Test("The exemption never suppresses wrongly-visible offenders")
    func exemptionNeverSuppressesWronglyVisible() {
        let split = offenders(
            currentVisible: ["a", "b", "ejected"],
            currentHidden: ["c"],
            desiredVisible: ["a", "b"],
            desiredHidden: ["c", "ejected"],
            desiredAlwaysHidden: [],
            overflowExemptUIDs: ["ejected"]
        )
        #expect(split.wronglyVisible == ["ejected"])
        #expect(split.wronglyConcealed.isEmpty)
        #expect(split.count == 1)
    }

    /// The exemption parameter defaults to empty; every pre-existing caller
    /// relies on that meaning "no exemption". Pin the identity so a default-
    /// value regression cannot silently change long-standing tallies.
    @Test("An empty exempt set reproduces the legacy tally exactly")
    func emptyExemptSetMatchesLegacyTally() {
        let inputs = (
            currentVisible: Set(["a", "b", "x"]),
            currentHidden: Set(["c", "d"]),
            currentAlwaysHidden: Set(["e"]),
            desiredVisible: Set(["a", "d"]),
            desiredHidden: Set(["b", "c"]),
            desiredAlwaysHidden: Set(["e"])
        )
        let legacy = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: inputs.currentVisible,
            currentHidden: inputs.currentHidden,
            currentAlwaysHidden: inputs.currentAlwaysHidden,
            desiredVisible: inputs.desiredVisible,
            desiredHidden: inputs.desiredHidden,
            desiredAlwaysHidden: inputs.desiredAlwaysHidden
        )
        let explicitEmpty = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: inputs.currentVisible,
            currentHidden: inputs.currentHidden,
            currentAlwaysHidden: inputs.currentAlwaysHidden,
            desiredVisible: inputs.desiredVisible,
            desiredHidden: inputs.desiredHidden,
            desiredAlwaysHidden: inputs.desiredAlwaysHidden,
            overflowExemptUIDs: []
        )
        // Both directions of travel are populated here, so this pins the
        // identity for wronglyVisible and wronglyConcealed at once.
        #expect(explicitEmpty == legacy)
        #expect(legacy.wronglyVisible == ["b"])
        #expect(legacy.wronglyConcealed == ["d"])
    }

    /// UIDs in the exempt set that name no item on the bar must change
    /// nothing: the eject set can outlive the items it once named (an app
    /// quits between cycles), and stale entries must be inert.
    @Test("Exempt UIDs that match nothing on the bar are inert")
    func unknownExemptUIDsAreInert() {
        let baseline = offenders(
            currentVisible: ["a"],
            currentHidden: ["c", "gone-before", "drifted"],
            desiredVisible: ["a", "drifted"],
            desiredHidden: ["c"]
        )
        #expect(baseline.wronglyConcealed == ["drifted"])
        let exempted = offenders(
            currentVisible: ["a"],
            currentHidden: ["c", "gone-before", "drifted"],
            desiredVisible: ["a", "drifted"],
            desiredHidden: ["c"],
            overflowExemptUIDs: ["never-existed", "quit-app:Item-0"]
        )
        #expect(exempted == baseline)
    }

    /// A tight bar can hold several ejected items at once. Exempting a
    /// subset absorbs exactly that subset; the rest keep counting.
    @Test("A partial exempt set absorbs only its own items")
    func partialExemptionAbsorbsOnlyItsOwnItems() {
        let split = offenders(
            currentVisible: ["a"],
            currentHidden: ["c", "ej1", "ej2", "ej3"],
            desiredVisible: ["a", "ej1", "ej2", "ej3"],
            desiredHidden: ["c"],
            desiredAlwaysHidden: [],
            overflowExemptUIDs: ["ej1", "ej3"]
        )
        #expect(split.wronglyConcealed == ["ej2"])
    }

    /// `hiddenBoundaryMismatch` is the value the parked-divider recovery
    /// streak counts on, so it must see the exempted tally too — an
    /// eject-only divergence must neither advance nor reset the streak's
    /// input dishonestly.
    @Test("hiddenBoundaryMismatch honours the exemption")
    func mismatchHonoursExemption() {
        let mismatchCurrentVisible = Set(["a", "b"])
        let currentHidden = Set(["c", "ejected"])
        let desiredVisible = Set(["a", "b", "ejected"])
        let desiredHidden = Set(["c"])

        let unexempt = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: mismatchCurrentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: [],
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: []
        )
        let exempt = LayoutSolver.hiddenBoundaryMismatch(
            currentVisible: mismatchCurrentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: [],
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: [],
            overflowExemptUIDs: ["ejected"]
        )
        #expect(unexempt == 1)
        #expect(exempt == 0)
    }

    /// applyProfileLayout derives the soak diagnostic without re-running the
    /// solver, as |exempt ∩ currentHidden ∩ desiredVisible|. That shortcut is
    /// only valid while the solver drops wronglyConcealed entries exclusively
    /// through that same intersection. Walk every placement of the exempt UID
    /// across the three sections and confirm the two computations agree.
    @Test("Absorbed-offender count equals the exempt intersection in every placement")
    func absorbedCountMatchesExemptIntersectionEverywhere() {
        let placements: [(section: String, currentHidden: Set<String>, currentAH: Set<String>)] = [
            (section: "hidden", currentHidden: ["ejected"], currentAH: []),
            (section: "always-hidden", currentHidden: [], currentAH: ["ejected"]),
            (section: "visible", currentHidden: [], currentAH: []),
            (section: "nowhere", currentHidden: [], currentAH: []),
        ]

        for placement in placements {
            let currentVisible = Set(["a", "b"] + (placement.section == "visible" ? ["ejected"] : []))
            let desiredVisible = Set(["a", "b", "ejected"])

            let unexempt = LayoutSolver.hiddenBoundaryOffenders(
                currentVisible: currentVisible,
                currentHidden: placement.currentHidden,
                currentAlwaysHidden: placement.currentAH,
                desiredVisible: desiredVisible,
                desiredHidden: ["c"],
                desiredAlwaysHidden: []
            )
            let exemptSet: Set = ["ejected"]
            let exempt = LayoutSolver.hiddenBoundaryOffenders(
                currentVisible: currentVisible,
                currentHidden: placement.currentHidden,
                currentAlwaysHidden: placement.currentAH,
                desiredVisible: desiredVisible,
                desiredHidden: ["c"],
                desiredAlwaysHidden: [],
                overflowExemptUIDs: exemptSet
            )

            let absorbed = unexempt.count - exempt.count
            let shortcut = exemptSet.intersection(placement.currentHidden)
                .intersection(desiredVisible).count
            #expect(
                absorbed == shortcut,
                "Placement \(placement.section): solver absorbed \(absorbed) but the orchestrator shortcut computes \(shortcut)"
            )
        }
    }

    /// Covers ``LayoutSolver.HiddenBoundaryOffenders/isEmpty`` directly: it
    /// gates nothing today but is the readable spelling future callers will
    /// reach for, so its agreement with count must not drift.
    @Test("isEmpty agrees with count")
    func isEmptyAgreesWithCount() {
        let empty = offenders(
            currentVisible: ["a"],
            currentHidden: [],
            desiredVisible: ["a"],
            desiredHidden: []
        )
        #expect(empty.isEmpty)

        let occupied = offenders(
            currentVisible: ["a", "b"],
            currentHidden: [],
            desiredVisible: ["a"],
            desiredHidden: ["b"]
        )
        #expect(!occupied.isEmpty)
        #expect(occupied.count == 1)
    }
}
