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
