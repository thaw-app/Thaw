//
//  HiddenDividerBoundaryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The hidden-divider boundary check applyProfileLayout's Phase 1 runs before
/// placing the always-hidden divider.
///
/// Neither earlier mechanism sees a divider that drifted past every managed item:
/// the Phase 1 tallies intersect occupied hidden sets (empty here, so zero), and
/// the LCS pass strips dividers (so current equals desired). Together they
/// classified every hidden item visible and reported success (#879).
@Suite("Hidden divider boundary")
struct HiddenDividerBoundaryTests {
    // MARK: - Mismatch counting

    /// A matching bar scores zero, so the divider move never runs on a healthy layout.
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

    /// The divider can drift the other way and swallow items meant to be visible.
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

    /// Which concealed section an item lands in is AH_ctrl's job; the hidden divider
    /// only decides concealed versus visible.
    @Test("Hidden and always-hidden are one side for this check")
    func hiddenAndAlwaysHiddenCountAsOneSide() {
        // Everything is concealed as intended, just in the wrong concealed section.
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

    /// Items the profile does not mention are routed by planUnmanagedPlacement and must not move the divider.
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

    /// Order runs right-to-left, so hidden index 0 is rightmost and the divider goes just right of it.
    @Test("The anchor is the rightmost live hidden item")
    func anchorsToRightmostHiddenItem() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["h1", "h2", "h3"],
            desiredVisible: ["v1", "v2"],
            liveMovableUIDs: ["h1", "h2", "h3", "v1", "v2"]
        )

        #expect(anchor == .rightOf("h1"))
    }

    /// Profiles list items that are not running, so the planner walks inward to one on the bar.
    @Test("A hidden item that is not running is skipped as an anchor")
    func skipsHiddenItemsThatAreNotLive() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["notRunning", "h2", "h3"],
            desiredVisible: ["v1"],
            liveMovableUIDs: ["h2", "h3", "v1"]
        )

        #expect(anchor == .rightOf("h2"))
    }

    /// With no live hidden item, the divider anchors left of the leftmost visible item (the last entry).
    @Test("An empty hidden side anchors left of the leftmost visible item")
    func fallsBackToLeftmostVisibleItem() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: ["notRunning"],
            desiredVisible: ["v1", "v2", "v3"],
            liveMovableUIDs: ["v1", "v2", "v3"]
        )

        #expect(anchor == .leftOf("v3"))
    }

    /// The caller logs and falls through to the LCS pass rather than guessing.
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

    /// Replays the Phase 1 sets from the #879 log, where the hidden section emptied
    /// into visible after 2.0.0-rc.1 to rc.2 and could not be restored: both tallies
    /// were 0 with 29 items desired hidden and none currently hidden.
    @Suite("Issue 879 field log")
    struct Issue879FieldLog {
        /// The 28 visible items in log order (index 0 rightmost).
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

        /// Phase 1 logs sorted sets, so this is membership only; order-dependent tests use synthetic fixtures.
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

        /// Every item belongs to one of the two sections and the bar already groups
        /// them (10 visible rightmost, 18 hidden). Only the divider is misplaced.
        @Test("The bar is cleanly partitioned; only the divider is misplaced")
        func barIsCleanlyPartitioned() {
            let boundVisible = Self.currentVisible.filter(Self.desiredVisible.contains)
            let boundHidden = Self.currentVisible.filter(Self.desiredHidden.contains)

            #expect(boundVisible.count == 10)
            #expect(boundHidden.count == 18)
            #expect(boundVisible + boundHidden == Self.currentVisible,
                    "the bar is already grouped visible-then-hidden, so only H_ctrl sits in the wrong gap")
        }

        /// With dividers stripped the two sequences are identical, so the LCS plans
        /// nothing, matching the log. Characterization, not regression: it pins the
        /// blindness the boundary check compensates for.
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

        /// The boundary check counts the 18 stranded items, which makes Phase 1 drag H_ctrl.
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

        /// With no always-hidden section `ahCtrlUID` was nil, so the existing repair
        /// branch could not run; the boundary move must not share that gate.
        @Test("The boundary is repairable without an always-hidden divider")
        func repairDoesNotDependOnAlwaysHiddenDivider() {
            let live = Set(Self.currentVisible)
            let anchor = LayoutSolver.planHiddenDividerAnchor(
                // The 18 stranded items in bar order.
                desiredHidden: Self.currentVisible.filter(Self.desiredHidden.contains),
                desiredVisible: Self.currentVisible.filter(Self.desiredVisible.contains),
                liveMovableUIDs: live
            )

            #expect(anchor == .rightOf("com.apphousekitchen.aldente-pro:Item-0"),
                    "H_ctrl belongs immediately right of the rightmost hidden item")
        }
    }
}

/// Keeps the H_ctrl boundary move off Thaw's own chevron (#958).
///
/// Candidates are pre-filtered to movable, on-screen items, which control items
/// always are. With the profile's items parked on the wrong side, the chevron is
/// the last candidate, and dragging H_ctrl to it sweeps the section across.
///
/// ```
/// Profile layout Phase 1: hiddenBoundaryMismatch=11
/// Profile layout: 11 item(s) on the wrong side of H_ctrl, moving H_ctrl to the boundary
/// Profile layout: moving H_ctrl -> left of <com.stonerl.Thaw:Thaw.ControlItem.Visible>
/// post-H_ctrl classification crossSectionMoves=0, totalSectionMismatch=0
/// ```
///
/// The roster is the visible order from the issue's `broken_profile.json`
/// (index 0 rightmost): the chevron at index 11 with four unmovable items left of it.
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

    /// Every hidden-side and real visible item parked, leaving only the chevron.
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

    /// Pins the old behaviour so the regression is caught by its shape, not only its absence.
    @Test("Without the bar, the same inputs anchor on the chevron")
    func sameInputsUsedToAnchorOnTheChevron() {
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron]
        )

        #expect(anchor == .leftOf(Self.chevron))
    }

    /// The next candidate right of the chevron is wanted visible, so anchoring there
    /// would conceal it: the same collapse, one item smaller.
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

    /// A divider in the desired-hidden order is refused the same way.
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

    /// Not a blanket stand-down on bars with the chevron live.
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

    /// The hidden side is tried first, so the common repair plans the same move as before.
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

    /// Lets a log tell "wrong side" from "not running".
    @Test("The candidate helper names the refused chevron")
    func candidateHelperNamesTheRefusedChevron() {
        let candidate = LayoutSolver.hiddenDividerAnchorCandidate(
            desiredHidden: Self.desiredHidden,
            desiredVisible: Self.desiredVisible,
            liveMovableUIDs: [Self.chevron]
        )

        #expect(candidate == Self.chevron)
    }

    /// The pre-existing nil, with its own log line.
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

/// Which of the two boundary repairs Phase 1 takes.
///
/// Dragging H_ctrl re-sections every item it crosses, so it only fits when the
/// divider itself drifted. With one item wrong and nine correctly concealed, the
/// drag would have carried the divider from -3871 to 1648 (#958).
@Suite("Divider drag versus per-item boundary moves")
struct HiddenBoundaryRepairChoiceTests {
    @Test("Nothing concealed means the divider drifted past everything (#879)")
    func emptyConcealedSideDragsTheDivider() {
        // Eighteen managed items all reading visible, none behind the divider.
        #expect(LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 0, liveVisibleCount: 18))
    }

    @Test("Nothing visible is the collapsed bar, and the drag is the recovery (#958)")
    func emptyVisibleSideDragsTheDivider() {
        #expect(LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 19, liveVisibleCount: 0))
    }

    @Test("One stray item with a populated hidden section moves the item (#958)")
    func oneStrayItemMovesTheItem() {
        // Nine correctly concealed, one on the wrong side: the divider is fine.
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: 9, liveVisibleCount: 17))
    }

    @Test("A bar with most items concealed still moves items, not the divider")
    func mostlyConcealedBarMovesItems() {
        // Thirty-two concealed, eleven of them wrongly.
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
        // The tally is defined by the split; these cases keep the two from drifting apart.
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
        // Moves between hidden and always-hidden are AH_ctrl's problem.
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

    /// A notch-overflow-ejected item sits concealed while the profile lists it
    /// visible, by design. Counting it makes Phase 1 recall it and the next overflow
    /// plan eject it again, oscillating while the bar is over budget.
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

        // Documents the oscillation mechanism, not desired behavior.
        let unexempt = offenders(
            currentVisible: ["a", "b"],
            currentHidden: ["c", "ejected"],
            desiredVisible: ["a", "b", "ejected"],
            desiredHidden: ["c"]
        )
        #expect(unexempt.wronglyConcealed == ["ejected"])
    }

    /// Drifting into always-hidden is real drift and keeps counting, as in `currentLayoutDivergesFromSaved`.
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

    /// The exempt set must not swallow unrelated wrongly-concealed items.
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

    /// An exempt UID sitting visible but wanted concealed is a real offender in the other direction.
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

    /// Every existing caller relies on the empty default meaning "no exemption".
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
        // Both directions are populated, so this pins wronglyVisible and wronglyConcealed at once.
        #expect(explicitEmpty == legacy)
        #expect(legacy.wronglyVisible == ["b"])
        #expect(legacy.wronglyConcealed == ["d"])
    }

    /// The eject set can outlive its items (an app quits), so stale entries must be inert.
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

    /// Exempting a subset absorbs exactly that subset.
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

    /// The parked-divider recovery streak counts on this value, so it must honour the exemption.
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

    /// applyProfileLayout computes the soak diagnostic as |exempt ∩ currentHidden ∩ desiredVisible|
    /// without re-running the solver; valid only while the solver drops wronglyConcealed
    /// entries through that same intersection. Every placement is checked.
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

    /// Unused today, but it must keep agreeing with count.
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
