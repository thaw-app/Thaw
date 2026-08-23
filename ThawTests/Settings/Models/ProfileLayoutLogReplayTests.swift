//
//  ProfileLayoutLogReplayTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Log-replay harness for the profile-layout decision path.
///
/// Parses real Thaw log lines into per-cycle records and drives the actual
/// pure planner (LayoutSolver.partitionUnmanagedUIDs) with inputs
/// reconstructed from those records. This characterizes "given the menu bar
/// shape Thaw observed on this cycle, did the planner deem the right items
/// unmanaged" without standing up the async orchestrator, AX, or the Window
/// Server. New field logs become regression fixtures by adding another
/// excerpt and another expectation.
///
/// Fixture one is LittleSnitchOrphanLog: a user whose Little Snitch agent
/// kept moving on launch. Its agent icon is hosted by Control Center with no
/// resolvable source PID, so it is namespaced com.apple.controlcenter:Item-0
/// and, not matching the profile's at.obdev.littlesnitch.agent:Item-0 entry,
/// is treated as an unmanaged new arrival and relocated every cycle until
/// marker-pair resolution finally identifies it ~46 minutes in.
///
/// The Layer-1 fix excludes provisional-identity orphans from the unmanaged
/// set inside the live partitioner. Two tests pin it down:
/// testWithoutExclusionTheOrphanWouldBeUnmanaged documents the bug mechanism
/// (with no exclusion the orphan is classified unmanaged, matching the field
/// log), and testBuggyCycleDoesNotPlanMoveForUnresolvedOrphan is the regression
/// lock that fails before the fix and passes after it.
@Suite("Profile layout log replay")
struct ProfileLayoutLogReplayTests {
    private let orphanUID = "com.apple.controlcenter:Item-0"

    // MARK: Parser characterization

    /// The parser recovers both applyProfileLayout cycles and the field
    /// verdict each one logged: one unmanaged item in the buggy cycle, none
    /// in the post-resolution clean cycle.
    @Test("The parser recovers both cycles and the verdict each one logged")
    func parserRecoversBothCyclesAndLoggedVerdicts() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)

        #expect(parsed.cycles.count == 2)
        #expect(
            parsed.unresolvedSourcePIDBaseUIDs.contains(orphanUID),
            "Missing sourcePID line should mark the orphan as unresolved"
        )

        let buggy = try #require(parsed.cycles.first)
        #expect(buggy.loggedUnmanagedUIDs == [orphanUID])
        #expect(buggy.currentVisible.contains(orphanUID))

        let clean = try #require(parsed.cycles.last)
        #expect(clean.loggedUnmanagedUIDs == [])
        #expect(clean.currentVisible.contains("at.obdev.littlesnitch.agent:Item-0"))
    }

    /// Fails with a clear message naming the specific log line if the parser
    /// ever stops recognising a format it currently understands, rather than
    /// surfacing a bare nil three layers away from the cause.
    ///
    /// LittleSnitchOrphanLog exercises 7 of the 9 format-contract patterns
    /// (see parse(_:)'s doc comment): Missing sourcePID, the three
    /// applyProfileLayout current-section lines, ahCtrlUID, desiredHidden, and
    /// desiredAH, plus a planUnmanagedPlacement line. It does NOT cover
    /// desiredVisible (older captures do not log it; see
    /// testLoggedDesiredVisibleIsUsedInsteadOfInference) or the two
    /// notch-overflow lines (see testDisplayReconnectNegativeBudgetYieldsNoOverflow).
    @Test("The parser recognises every format-contract pattern in the fixture")
    func parserRecognisesEveryFormatContractPatternInTheFixture() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)

        #expect(
            parsed.unresolvedSourcePIDBaseUIDs.contains(orphanUID),
            "Parser did not extract an unresolved sourcePID. The 'Missing sourcePID for' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )

        let cycle = try #require(parsed.cycles.first)

        #expect(
            !cycle.currentVisible.isEmpty,
            "Parser did not extract currentVisible. The 'applyProfileLayout: current visible section' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
        #expect(
            !cycle.currentHidden.isEmpty,
            "Parser did not extract currentHidden. The 'applyProfileLayout: current hidden section' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
        #expect(
            !cycle.currentAlwaysHidden.isEmpty,
            "Parser did not extract currentAlwaysHidden. The 'applyProfileLayout: current always-hidden section' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
        #expect(
            cycle.ahCtrlUID != nil,
            "Parser did not extract ahCtrlUID. The 'Profile layout Phase 1: ahCtrlUID=' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
        #expect(
            !cycle.desiredHidden.isEmpty,
            "Parser did not extract desiredHidden. The 'Profile layout Phase 1: desiredHidden=' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
        #expect(
            !cycle.desiredAlwaysHidden.isEmpty,
            "Parser did not extract desiredAH. The 'Profile layout Phase 1: desiredAH=' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
        #expect(
            !cycle.loggedUnmanagedUIDs.isEmpty,
            "Parser did not extract loggedUnmanagedUIDs. The 'Profile layout: planUnmanagedPlacement' log message in MenuBarItemManager.swift was probably reworded — see format-contract comments."
        )
    }

    // MARK: Bug mechanism (documents what the exclusion is responsible for)

    /// With no orphan exclusion (provisionalIdentityUIDs empty), replaying the
    /// buggy cycle through the real partitioner reproduces the field verdict
    /// exactly: the unresolved Little Snitch orphan is the sole item routed to
    /// planUnmanagedPlacement, which is what dragged it on every cycle. The
    /// unmanaged set is reconstructed independently of the planUnmanagedPlace-
    /// ment log lines (the orphan is identified via the Missing sourcePID
    /// signal), so matching them is a genuine characterization, not a tautology.
    @Test("Without the exclusion the orphan is classified unmanaged")
    func withoutExclusionTheOrphanWouldBeUnmanaged() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let buggy = try #require(parsed.cycles.first)
        let inputs = buggy.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)

        #expect(inputs.provisionalIdentityOrphans == [orphanUID])

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            provisionalIdentityUIDs: []
        )

        #expect(result == buggy.loggedUnmanagedUIDs)
        #expect(result == [orphanUID])
    }

    // MARK: Regression lock for Layer 1 (red before the fix, green after)

    /// Replaying the buggy cycle through the live partitioner, passing the
    /// orphan set the orchestrator now computes, the unresolved Little Snitch
    /// orphan is no longer classified unmanaged, so no unmanaged placement (and
    /// therefore no move) is planned for it. This fails before Layer 1 applies
    /// provisionalIdentityUIDs and passes once it does.
    @Test("The buggy cycle plans no move for the unresolved orphan")
    func buggyCycleDoesNotPlanMoveForUnresolvedOrphan() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let buggy = try #require(parsed.cycles.first)
        let inputs = buggy.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)

        // The field log confirms this orphan WAS classified unmanaged and moved.
        #expect(buggy.loggedUnmanagedUIDs.contains(orphanUID))
        #expect(inputs.provisionalIdentityOrphans == [orphanUID])

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            provisionalIdentityUIDs: inputs.provisionalIdentityOrphans
        )

        #expect(
            !result.contains(orphanUID),
            "Unresolved Little Snitch orphan must not be classified unmanaged"
        )
        #expect(result.isEmpty)
    }

    // MARK: Baseline: the clean cycle stays clean

    /// After marker-pair resolution the same physical item is namespaced
    /// at.obdev.littlesnitch.agent:Item-0, which the profile knows, so the
    /// unchanged partitioner already deems nothing unmanaged. This guards
    /// against a fix that over-suppresses correctly-identified items.
    @Test("The clean cycle has nothing unmanaged under the current partition")
    func cleanCycleHasNoUnmanagedUnderCurrentPartition() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let clean = try #require(parsed.cycles.last)
        let inputs = clean.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)

        #expect(inputs.provisionalIdentityOrphans.isEmpty)

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            provisionalIdentityUIDs: inputs.provisionalIdentityOrphans
        )

        #expect(result == clean.loggedUnmanagedUIDs)
        #expect(result.isEmpty)
    }

    // MARK: Live wiring: control identifiers come from live tags

    /// The control identifiers the harness feeds the partitioner are derived
    /// from the live control-item tags, and they match what the field log
    /// recorded. If a control item's namespace or title changes in the Thaw
    /// codebase, this fails rather than silently diverging from real logs.
    @Test("The live control item UIDs match the field log")
    func liveControlItemUIDsMatchTheFieldLog() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let buggy = try #require(parsed.cycles.first)

        #expect(
            MenuBarItemTag.alwaysHiddenControlItem.tagIdentifier == buggy.ahCtrlUID,
            "Live always-hidden control tag should equal the logged ahCtrlUID"
        )
        #expect(
            buggy.currentVisible.contains(MenuBarItemTag.visibleControlItem.tagIdentifier),
            "Live visible control tag should appear in the logged visible section"
        )
    }

    // MARK: Hardening: prefer the logged desiredVisible over inference

    /// With the Phase 1 desiredVisible line present, the harness uses it
    /// verbatim instead of inferring desired-visible from the current bar.
    /// Constructed so the two paths disagree: `com.example.extra:Item-0` is a
    /// non-orphan visible item the profile does not cover, so inference (which
    /// keeps every non-orphan visible item) would wrongly treat it as desired
    /// and never flag it, whereas the logged desiredVisible omits it and the
    /// partitioner correctly classifies it unmanaged, matching the log.
    @Test("The logged desiredVisible is used instead of inference")
    func loggedDesiredVisibleIsUsedInsteadOfInference() throws {
        let log = """
        2026-05-30 09:00:00.000 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 3 items: ["com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.example.extra:Item-0", "com.rogueamoeba.soundsource:SSMainAppMenuIcon"]
        2026-05-30 09:00:00.001 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 0 items: []
        2026-05-30 09:00:00.002 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 0 items: []
        2026-05-30 09:00:00.003 [DEBUG] [MenuBarItemManager] Profile layout: planUnmanagedPlacement com.example.extra:Item-0 -> newItemDefault(section=hidden section)
        2026-05-30 09:00:00.004 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: ahCtrlUID=com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden, crossSectionMoves=0, totalSectionMismatch=0
        2026-05-30 09:00:00.004 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredHidden=[]
        2026-05-30 09:00:00.004 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredAH=[]
        2026-05-30 09:00:00.004 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredVisible=["com.rogueamoeba.soundsource:SSMainAppMenuIcon"]
        """

        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)
        #expect(cycle.desiredVisible == ["com.rogueamoeba.soundsource:SSMainAppMenuIcon"])

        let inputs = cycle.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)
        #expect(inputs.provisionalIdentityOrphans.isEmpty)

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            provisionalIdentityUIDs: inputs.provisionalIdentityOrphans
        )

        #expect(result == ["com.example.extra:Item-0"])
        #expect(result == cycle.loggedUnmanagedUIDs)
    }

    // MARK: Regression lock for the display-reconnect overflow corruption (#666)

    /// Replays a real field cycle (thaw_2026-06-07_09-48-52.log, 11:44:42)
    /// where a display disconnect/reconnect left the menu bar geometry
    /// unsettled: Control Center reported a stale off-screen edge, so the
    /// overflow budget came out negative (availableWidth=-1202) and the buggy
    /// build ejected all 13 visible items into hidden, collapsing the hidden
    /// section into visible. Driving the live planNotchOverflow with that exact
    /// budget must yield no overflow once the invalid-budget guard is in place.
    /// Red before the guard (every visible item ejected), green after.
    @Test("A negative field budget from a display reconnect yields no overflow")
    func displayReconnectNegativeBudgetYieldsNoOverflow() throws {
        let log = """
        2026-06-07 11:44:42.027 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 4 items: ["leits.MeetingBar:Item-0", "eu.exelban.Stats:CPU_bar_chart", "com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.apple.TextInputMenuAgent:Item-0"]
        2026-06-07 11:44:42.027 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 3 items: ["com.electron.dockerdesktop:Item-0", "com.apple.controlcenter:WiFi", "com.kaspersky.kav_agent:Item-0"]
        2026-06-07 11:44:42.027 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 2 items: ["ru.keepcoder.Telegram:Item-0", "com.apple.controlcenter:Battery"]
        2026-06-07 11:44:42.028 [DEBUG] [MenuBarItemManager] Notch overflow budget: screen.maxX=1728.0 notch=[771.0…956.0] rightBoundary=-222.0 availableWidth=-1202.0 userSpacing=0.0 visibleUIDs.count=14 nonProfileCount=0 nonProfileFootprint=0.0 chevronFootprint=0.0 nonProfileBreakdown=[]
        2026-06-07 11:44:42.028 [INFO] [MenuBarItemManager] Profile layout: notch overflow; 13 item(s) moved from visible to hidden
        """

        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)

        // Field characterization: the reconnect produced an invalid (negative)
        // budget, and the buggy build ejected 13 items from visible.
        #expect(cycle.notchAvailableWidth == -1202)
        #expect(cycle.loggedOverflowCount == 13)

        // Reconstruct a desiredFiltered flat order from the cycle and drive the
        // live planner with the real (negative) budget. Widths are any positive
        // value; the guard must short-circuit before widths matter.
        let visibleCtrl = MenuBarItemTag.visibleControlItem.tagIdentifier
        let hiddenCtrl = MenuBarItemTag.hiddenControlItem.tagIdentifier
        let ahCtrl = MenuBarItemTag.alwaysHiddenControlItem.tagIdentifier

        var desiredFiltered = cycle.currentVisible
        desiredFiltered.append(hiddenCtrl)
        desiredFiltered.append(contentsOf: cycle.currentHidden)
        desiredFiltered.append(ahCtrl)
        desiredFiltered.append(contentsOf: cycle.currentAlwaysHidden)

        var uidWidths = [String: CGFloat]()
        for uid in desiredFiltered {
            uidWidths[uid] = 24
        }

        let availableWidth = try #require(cycle.notchAvailableWidth)
        let result = try LayoutSolver.planNotchOverflow(
            desiredFiltered: desiredFiltered,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: visibleCtrl, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: [:],
            uidWidths: uidWidths,
            availableWidth: availableWidth
        )

        #expect(
            result.overflowUIDs.isEmpty,
            "Negative field budget (-1202) must not eject any item once guarded; the buggy build ejected \(cycle.loggedOverflowCount ?? -1)"
        )
        #expect(result.updatedDesiredFiltered == desiredFiltered)
    }

    // MARK: Regression lock for the unsettled-geometry layout pass

    /// Replays a real field cycle (thaw_2026-06-11_09-11-10.log, 11:31:05) on
    /// the patched build where the notch-overflow guard is already present:
    /// Control Center was reported at rightBoundary=672, left of the notch's
    /// right edge (956), giving a negative budget. The overflow guard correctly
    /// skipped the eject, but the pass still ran its control-item placement on
    /// that stale geometry and moved the Thaw visible icon to the far left. The
    /// geometry-readiness gate must report this cycle as not ready so the whole
    /// pass is deferred. Red before the gate (the stub reports ready).
    @Test("An unsettled-geometry field cycle is not ready")
    func unsettledGeometryFieldCycleIsNotReady() throws {
        let log = """
        2026-06-11 11:31:05.750 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 1 items: ["leits.MeetingBar:Item-0"]
        2026-06-11 11:31:05.750 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 0 items: []
        2026-06-11 11:31:05.750 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 0 items: []
        2026-06-11 11:31:05.751 [DEBUG] [MenuBarItemManager] Notch overflow budget: screen.maxX=1728.0 notch=[771.0…956.0] rightBoundary=672.0 availableWidth=-308.0 userSpacing=0.0 visibleUIDs.count=14 nonProfileCount=0 nonProfileFootprint=0.0 chevronFootprint=0.0 nonProfileBreakdown=[]
        """
        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)

        #expect(cycle.notchRightBoundary == 672)
        #expect(cycle.notchMaxX == 956)

        let rightBoundary = try #require(cycle.notchRightBoundary)
        let notchMaxX = try #require(cycle.notchMaxX)

        #expect(
            !LayoutSolver.isMenuBarGeometryReady(rightBoundary: rightBoundary, notchMaxX: notchMaxX),
            "Control Center reported left of the notch (672 <= 956) is unsettled geometry; the pass must defer"
        )
    }

    /// A settled field cycle (rightBoundary 1562, right of the notch 956) is
    /// ready and must not be deferred. Guards against a gate that blocks valid
    /// layouts.
    @Test("A settled-geometry field cycle is ready")
    func settledGeometryFieldCycleIsReady() throws {
        let log = """
        2026-06-11 13:13:58.558 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 1 items: ["leits.MeetingBar:Item-0"]
        2026-06-11 13:13:58.558 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 0 items: []
        2026-06-11 13:13:58.558 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 0 items: []
        2026-06-11 13:13:58.559 [DEBUG] [MenuBarItemManager] Notch overflow budget: screen.maxX=1728.0 notch=[771.0…956.0] rightBoundary=1562.0 availableWidth=565.0 userSpacing=0.0 visibleUIDs.count=14 nonProfileCount=0 nonProfileFootprint=0.0 chevronFootprint=17.0 nonProfileBreakdown=[]
        """
        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)

        #expect(cycle.notchRightBoundary == 1562)
        #expect(cycle.notchMaxX == 956)

        let rightBoundary = try #require(cycle.notchRightBoundary)
        let notchMaxX = try #require(cycle.notchMaxX)

        #expect(LayoutSolver.isMenuBarGeometryReady(rightBoundary: rightBoundary, notchMaxX: notchMaxX))
    }

    /// Boundary cases for the pure gate: strictly right of the notch is ready;
    /// at the edge, left of it, or non-finite is not.
    @Test("Only a boundary strictly right of the notch reads as ready")
    func geometryReadyBoundaries() {
        #expect(LayoutSolver.isMenuBarGeometryReady(rightBoundary: 957, notchMaxX: 956))
        #expect(!LayoutSolver.isMenuBarGeometryReady(rightBoundary: 956, notchMaxX: 956))
        #expect(!LayoutSolver.isMenuBarGeometryReady(rightBoundary: -222, notchMaxX: 956))
        #expect(!LayoutSolver.isMenuBarGeometryReady(rightBoundary: .infinity, notchMaxX: 956))
        #expect(!LayoutSolver.isMenuBarGeometryReady(rightBoundary: .nan, notchMaxX: 956))
    }

    // MARK: Regression lock for the overflow-eject vs boundary-repair oscillation (#958)

    /// Replays a real field cycle (thaw_2026-08-20_11-21-26.log, 16:32:47.8,
    /// nk-tedo-001's machine, build 52f4ed3): the bar is persistently over the
    /// notch budget, so every apply re-plans an eject ("notch overflow;
    /// 1 item(s)" fires at .826 and again 2.6 s later), while Phase 1 reads
    /// `leits.MeetingBar` — hidden in this cycle's snapshot, visible per the
    /// saved order — as wronglyConcealed. The log does not name which UID the
    /// eject plan chose, but it names the count (1), and MeetingBar is the
    /// one item the mismatch counted.
    ///
    /// On builds through e384ce36 that mismatch drove a divider drag; since
    /// aa5b2850 it drives per-item moves that recall MeetingBar to visible,
    /// and the next cycle's eject plan sends it back: two synthetic drags per
    /// apply, forever (the "icons jumping randomly" reports). With this
    /// cycle's overflow eject exempted, the boundary check scores zero and no
    /// repair chases the item.
    /// Red before the exemption (mismatch=1), green after (mismatch=0).
    @Test("An overflow-ejected field cycle must not count the ejected item as a boundary offender")
    func overflowEjectedFieldCycleIsNotABoundaryOffender() throws {
        let log = """
        2026-08-20 16:32:47.824 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 12 items: ["com.steipete.codexbar:codexbar-codex", "com.steipete.codexbar:codexbar-claude", "com.tunabellysoftware.tgpro:Item-0", "eu.exelban.Stats:CPU_bar_chart", "eu.exelban.Stats:GPU_bar_chart", "eu.exelban.Stats:RAM_bar_chart", "com.rogueamoeba.soundsource:SSMainAppMenuIcon", "com.rogueamoeba.soundsource:Input", "com.apphousekitchen.aldente-pro:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.Visible", "org.p0deje.Maccy:Item-0", "com.apple.TextInputMenuAgent:Item-0"]
        2026-08-20 16:32:47.825 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 9 items: ["leits.MeetingBar:Item-0", "com.electron.dockerdesktop:Item-0", "com.proxyman.NSProxy:Item-0", "com.techsmith.snagit.capturehelper:Item-0", "com.nektony.App-Cleaner-SIII-UIHelper:Item-0", "com.paloaltonetworks.GlobalProtect.client:Item-0", "com.apple.KerberosMenuExtra:Item-0", "com.apple.controlcenter:Battery", "com.kaspersky.kav_agent:Item-0"]
        2026-08-20 16:32:47.825 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 7 items: ["com.steipete.codexbar:codexbar-cursor", "com.nextcloud.desktopclient:Item-0", "ru.yandex.desktop.disk2:Item-0", "com.shortcutlabs.FlicMac:Item-0", "ru.keepcoder.Telegram:Item-0", "com.steipete.codexbar:codexbar-opencode", "com.apple.Spotlight:Item-0"]
        2026-08-20 16:32:47.826 [INFO] [MenuBarItemManager] Profile layout: notch overflow; 1 item(s) moved from visible to hidden
        2026-08-20 16:32:47.828 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: ahCtrlUID=com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden, crossSectionMoves=0, totalSectionMismatch=0
        2026-08-20 16:32:47.828 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredHidden=["com.apple.KerberosMenuExtra:Item-0", "com.apple.controlcenter:Battery", "com.apple.controlcenter:NowPlaying", "com.apple.controlcenter:WiFi", "com.electron.dockerdesktop:Item-0", "com.kaspersky.kav_agent:Item-0", "com.nektony.App-Cleaner-SIII-UIHelper:Item-0", "com.paloaltonetworks.GlobalProtect.client:Item-0", "com.proxyman.NSProxy:Item-0", "com.techsmith.snagit.capturehelper:Item-0"]
        2026-08-20 16:32:47.828 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredVisible=["com.apphousekitchen.aldente-pro:Item-0", "com.apple.TextInputMenuAgent:Item-0", "com.apple.controlcenter:BentoBox-0", "com.apple.controlcenter:Clock", "com.rogueamoeba.soundsource:Input", "com.rogueamoeba.soundsource:SSMainAppMenuIcon", "com.steipete.codexbar:codexbar-claude", "com.steipete.codexbar:codexbar-codex", "com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.tunabellysoftware.tgpro:Item-0", "eu.exelban.Stats:CPU_bar_chart", "eu.exelban.Stats:GPU_bar_chart", "eu.exelban.Stats:Network_speed", "eu.exelban.Stats:RAM_bar_chart", "leits.MeetingBar:Item-0", "org.p0deje.Maccy:Item-0"]
        2026-08-20 16:32:47.828 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: hiddenBoundaryMismatch=1
        """
        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try #require(parsed.cycles.first)

        // Field characterization: the buggy cycle counted exactly one
        // offender — the item this very cycle's overflow plan had stashed in
        // hidden.
        #expect(cycle.loggedOverflowCount == 1)
        let ejectedUID = "leits.MeetingBar:Item-0"
        #expect(cycle.currentHidden.contains(ejectedUID))
        #expect(cycle.desiredVisible?.contains(ejectedUID) == true)

        let currentVisible = Set(cycle.currentVisible)
        let currentHidden = Set(cycle.currentHidden)
        let currentAlwaysHidden = Set(cycle.currentAlwaysHidden)
        let desiredVisible = try Set(#require(cycle.desiredVisible))
        let desiredHidden = Set(cycle.desiredHidden)
        let desiredAlwaysHidden = Set(cycle.desiredAlwaysHidden)

        // Without the exemption the ejected item is the offender — this
        // documents the mechanism that sent the repair after it each cycle.
        let unexempt = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: currentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: currentAlwaysHidden,
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: desiredAlwaysHidden
        )
        #expect(unexempt.count == 1, "Field cycle logged hiddenBoundaryMismatch=1; replay disagrees")
        #expect(unexempt.wronglyConcealed == [ejectedUID])

        // With this cycle's overflow eject exempted, the by-design divergence
        // no longer counts and no repair may chase the item.
        let exempt = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: currentVisible,
            currentHidden: currentHidden,
            currentAlwaysHidden: currentAlwaysHidden,
            desiredVisible: desiredVisible,
            desiredHidden: desiredHidden,
            desiredAlwaysHidden: desiredAlwaysHidden,
            overflowExemptUIDs: [ejectedUID]
        )
        #expect(exempt.isEmpty, "Exempting this cycle's overflow eject must clear the field mismatch")

        // The gate itself stays false for these counts (nine correctly
        // concealed, eleven visible after control items are dropped), so on
        // aa5b2850+ builds the repair route was per-item drags — exactly the
        // oscillation this exemption removes.
        let liveControlUIDs: Set = ["com.stonerl.Thaw:Thaw.ControlItem.Visible",
                                    "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden"]
        let liveConcealed = currentHidden.union(currentAlwaysHidden).subtracting(liveControlUIDs).count
        let liveVisible = currentVisible.subtracting(liveControlUIDs).count
        #expect(!LayoutSolver.shouldMoveHiddenDivider(liveConcealedCount: liveConcealed, liveVisibleCount: liveVisible))
    }
}

/// Parses Thaw profile-layout log text into replayable cycles and drives the
/// real partitioner. Kept test-only; it models just enough of one
/// applyProfileLayout cycle to characterize the unmanaged-item decision.
enum ProfileLayoutLogReplay {
    /// One applyProfileLayout cycle reconstructed from the log.
    struct Cycle {
        var currentVisible: [String] = []
        var currentHidden: [String] = []
        var currentAlwaysHidden: [String] = []
        var desiredHidden: [String] = []
        var desiredAlwaysHidden: [String] = []
        /// The desired visible set, present only in logs from builds that emit
        /// the Phase 1 desiredVisible line. nil for older captures, in which
        /// case partitionInputs reconstructs it.
        var desiredVisible: [String]?
        var ahCtrlUID: String?
        /// UIDs the log actually routed through planUnmanagedPlacement this
        /// cycle (the field verdict the harness characterizes against).
        var loggedUnmanagedUIDs: [String] = []
        /// The notch-overflow budget the cycle logged, when present. A
        /// non-positive value means the menu bar geometry had not settled
        /// (Control Center reporting a stale off-screen edge), which the
        /// overflow planner must not act on.
        var notchAvailableWidth: CGFloat?
        /// How many items the cycle logged as overflowing visible -> hidden
        /// (the field verdict for the overflow planner).
        var loggedOverflowCount: Int?
        /// The notch's right edge (notch.maxX) from the budget line.
        var notchMaxX: CGFloat?
        /// The rightBoundary the cycle logged: Control Center's left edge, or
        /// the screen's right edge when Control Center is absent. The
        /// geometry-readiness gate compares this against notchMaxX.
        var notchRightBoundary: CGFloat?
    }

    /// The parsed result: the ordered cycles plus the set of menu bar items
    /// the log reported as having no resolved source PID.
    struct Parsed {
        let cycles: [Cycle]
        let unresolvedSourcePIDBaseUIDs: Set<String>
    }

    /// Inputs reconstructed for one cycle, shaped for partitionUnmanagedUIDs.
    struct PartitionInputs {
        let currentFlat: [String]
        let desiredUIDs: Set<String>
        let hiddenCtrlUID: String?
        let ahCtrlUID: String?
        let visibleCtrlUID: String?
        /// Items present this cycle whose identifier is only provisional
        /// (nil sourcePID, Control Center namespace). These are what the fix
        /// excludes.
        let provisionalIdentityOrphans: Set<String>
    }

    private static let visibleCtrlUID = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
    private static let hiddenCtrlUID = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"

    /// Parses a captured diagnostic log into replayable cycles.
    ///
    /// Each pattern below is a contract with a production `diagLog` call site.
    /// The emitting sites are marked with a matching
    /// `// Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:)`
    /// comment; find them with:
    ///
    ///     grep -rn 'Format contract: parsed by ProfileLayoutLogReplayTests' Thaw/
    ///
    /// The checked-in fixtures are real captured field logs that cannot be
    /// regenerated, so the production messages must not be reworded.
    static func parse(_ text: String) -> Parsed {
        var cycles = [Cycle]()
        var unresolved = Set<String>()
        var current: Cycle?

        func flush() {
            if let current {
                cycles.append(current)
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)

            if let match = line.firstMatch(of: /Missing sourcePID for <(.+?) \(windowID: \d+\)>/) {
                unresolved.insert(String(match.output.1))
                continue
            }

            if let match = line.firstMatch(
                of: /applyProfileLayout: current (visible|hidden|always-hidden) section has \d+ items: \[(.*)\]/
            ) {
                let section = String(match.output.1)
                let uids = quotedStrings(in: match.output.2)
                // A "current visible section" line opens a new cycle.
                if section == "visible" {
                    flush()
                    current = Cycle()
                    current?.currentVisible = uids
                } else if section == "hidden" {
                    current?.currentHidden = uids
                } else {
                    current?.currentAlwaysHidden = uids
                }
                continue
            }

            if let match = line.firstMatch(of: /Profile layout Phase 1: ahCtrlUID=([^,]+),/) {
                current?.ahCtrlUID = String(match.output.1)
                continue
            }

            if let match = line.firstMatch(of: /Profile layout Phase 1: desiredHidden=\[(.*)\]/) {
                current?.desiredHidden = quotedStrings(in: match.output.1)
                continue
            }

            if let match = line.firstMatch(of: /Profile layout Phase 1: desiredAH=\[(.*)\]/) {
                current?.desiredAlwaysHidden = quotedStrings(in: match.output.1)
                continue
            }

            if let match = line.firstMatch(of: /Profile layout Phase 1: desiredVisible=\[(.*)\]/) {
                current?.desiredVisible = quotedStrings(in: match.output.1)
                continue
            }

            if let match = line.firstMatch(of: /Profile layout: planUnmanagedPlacement (\S+) ->/) {
                current?.loggedUnmanagedUIDs.append(String(match.output.1))
                continue
            }

            if let match = line.firstMatch(
                of: /Notch overflow budget:.*notch=\[[0-9.]+…([0-9.]+)\] rightBoundary=(-?[0-9.]+) availableWidth=(-?[0-9.]+)/
            ) {
                current?.notchMaxX = Double(match.output.1).map { CGFloat($0) }
                current?.notchRightBoundary = Double(match.output.2).map { CGFloat($0) }
                current?.notchAvailableWidth = Double(match.output.3).map { CGFloat($0) }
                continue
            }

            if let match = line.firstMatch(of: /notch overflow; (\d+) item\(s\) moved from visible to hidden/) {
                current?.loggedOverflowCount = Int(match.output.1)
                continue
            }
        }
        flush()

        return Parsed(cycles: cycles, unresolvedSourcePIDBaseUIDs: unresolved)
    }

    /// Builds a live MenuBarItemTag from a logged uniqueIdentifier so the
    /// harness exercises the real tag predicates (isControlCenterGenericItem,
    /// isControlItem) and the real identifier format rather than reimplementing
    /// them. Identifiers are `namespace:title[:index]`; only a trailing
    /// all-digits component is the instance index, and titles may themselves
    /// contain dots (e.g. com.apple.menuextra.TimeMachine) but not colons.
    static func makeTag(fromUID uid: String, windowID: CGWindowID) -> MenuBarItemTag {
        var parts = uid.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let namespace = parts.removeFirst()
        var instanceIndex = 0
        if parts.count > 1, let last = parts.last, let index = Int(last), String(index) == last {
            instanceIndex = index
            parts.removeLast()
        }
        let title = parts.joined(separator: ":")
        return MenuBarItemTag(
            namespace: .string(namespace),
            title: title,
            windowID: windowID,
            instanceIndex: instanceIndex
        )
    }

    /// Builds live MenuBarItem objects for a cycle's current bar. Section
    /// membership and sourcePID resolution are observed state replayed from the
    /// log (an item is unresolved when its identifier appeared in a Missing
    /// sourcePID warning); everything derived from these items afterwards uses
    /// live Thaw code.
    static func makeCurrentItems(
        sectionOrderedUIDs: [String],
        unresolvedSourcePIDBaseUIDs: Set<String>,
        windowIDBase: CGWindowID
    ) -> [MenuBarItem] {
        sectionOrderedUIDs.enumerated().map { offset, uid in
            let windowID = windowIDBase + CGWindowID(offset)
            let tag = makeTag(fromUID: uid, windowID: windowID)
            let resolved = !unresolvedSourcePIDBaseUIDs.contains(uid)
            return MenuBarItem.fixture(
                tag: tag,
                windowID: windowID,
                sourcePID: resolved ? pid_t(Int(windowID)) : nil
            )
        }
    }

    /// Extracts the quoted UIDs from a logged array body like
    /// `"a", "b", "c"`.
    private static func quotedStrings(in body: Substring) -> [String] {
        body.matches(of: /"([^"]+)"/).map { String($0.output.1) }
    }
}

extension ProfileLayoutLogReplay.Cycle {
    /// Reconstructs partitionUnmanagedUIDs inputs for this cycle.
    ///
    /// When the log carries the Phase 1 desiredVisible line (builds that emit
    /// it), that captured set is used verbatim, so nothing about the desired
    /// layout is inferred. For older captures that predate the line, the
    /// visible desired set is reconstructed as the current visible items that
    /// are neither control items nor provisional-identity orphans, which is
    /// sound for those fixtures because the field log confirmed the orphan was
    /// the only visible item the profile did not cover.
    func partitionInputs(unresolvedSourcePIDBaseUIDs: Set<String>) -> ProfileLayoutLogReplay.PartitionInputs {
        // Control identifiers come from the live control-item tags, not
        // hardcoded strings, so a change to control-item identity is caught.
        let visibleCtrl = MenuBarItemTag.visibleControlItem.tagIdentifier
        let hiddenCtrl = MenuBarItemTag.hiddenControlItem.tagIdentifier
        let ahCtrl = MenuBarItemTag.alwaysHiddenControlItem.tagIdentifier

        // Live items for the current bar, per section; everything below is
        // derived from them through live Thaw code (uniqueIdentifier,
        // hasProvisionalIdentity) rather than from string heuristics.
        let visibleItems = ProfileLayoutLogReplay.makeCurrentItems(
            sectionOrderedUIDs: currentVisible,
            unresolvedSourcePIDBaseUIDs: unresolvedSourcePIDBaseUIDs,
            windowIDBase: 9000
        )
        let hiddenItems = ProfileLayoutLogReplay.makeCurrentItems(
            sectionOrderedUIDs: currentHidden,
            unresolvedSourcePIDBaseUIDs: unresolvedSourcePIDBaseUIDs,
            windowIDBase: 9100
        )
        let ahItems = ProfileLayoutLogReplay.makeCurrentItems(
            sectionOrderedUIDs: currentAlwaysHidden,
            unresolvedSourcePIDBaseUIDs: unresolvedSourcePIDBaseUIDs,
            windowIDBase: 9200
        )

        // currentFlat is built by the SAME pure helper applyProfileLayout uses,
        // so the harness exercises the real flatten / boundary-control logic.
        let currentFlat = LayoutSolver.flattenCurrentSections(
            visible: visibleItems.map(\.uniqueIdentifier),
            hidden: hiddenItems.map(\.uniqueIdentifier),
            alwaysHidden: ahItems.map(\.uniqueIdentifier),
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl
        )

        // The exact condition the Layer-1 fix excludes: an item left with a
        // provisional identifier because its source PID never resolved.
        // Computed with the live predicate so the harness tracks the
        // production predicate.
        let orphans = Set(
            (visibleItems + hiddenItems + ahItems)
                .filter(\.hasProvisionalIdentity)
                .map(\.uniqueIdentifier)
        )

        let desiredVisibleUIDs = desiredVisible ?? currentVisible.filter { uid in
            uid != visibleCtrl && uid != hiddenCtrl && uid != ahCtrl && !orphans.contains(uid)
        }

        let desiredUIDs = Set(desiredHidden)
            .union(desiredAlwaysHidden)
            .union(desiredVisibleUIDs)

        return ProfileLayoutLogReplay.PartitionInputs(
            currentFlat: currentFlat,
            desiredUIDs: desiredUIDs,
            hiddenCtrlUID: hiddenCtrl,
            ahCtrlUID: ahCtrl,
            visibleCtrlUID: visibleCtrl,
            provisionalIdentityOrphans: orphans
        )
    }
}

/// Red→green guard for the relaunch-settling gate
/// (MenuBarItemManager.tracksMenuBarItem). When a tracked app relaunches
/// (e.g. an in-app update) Thaw must arm a settling period so the move pass
/// waits out the churn; without it the bulk apply runs on the transient
/// layout and sweeps hidden items into the visible section (the Free Download
/// Manager update unhide). Equally it must NOT arm for ordinary launches, so
/// users don't pay a deferral on every app start, and one bundle ID must not
/// loosely prefix-match another app.
@Suite("Relaunch settling gate")
struct RelaunchSettlingGateTests {
    private let tracked: Set<String> = [
        "org.freedownloadmanager.fdm6:Item-0",
        "codes.rambo.AirBuddyHelper:codes.rambo.AirBuddy.Menu",
        "com.apple.controlcenter:WiFi",
    ]

    @Test("A tracked app relaunch arms the settling period")
    func trackedAppRelaunchArmsSettling() {
        #expect(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "org.freedownloadmanager.fdm6", in: tracked)
        )
    }

    @Test("An untracked app launch does not arm the settling period")
    func untrackedAppLaunchDoesNotArmSettling() {
        #expect(
            !MenuBarItemManager.tracksMenuBarItem(bundleID: "com.apple.Safari", in: tracked)
        )
    }

    @Test("A bundle ID that merely prefixes another does not match")
    func bundleIDPrefixBoundaryDoesNotFalseMatch() {
        // org.freedownloadmanager.fdm6 must not match a different app whose
        // bundle id merely extends it; the ":" separator anchors the match.
        let other: Set = ["org.freedownloadmanager.fdm6x:Item-0"]
        #expect(
            !MenuBarItemManager.tracksMenuBarItem(bundleID: "org.freedownloadmanager.fdm6", in: other)
        )
    }

    @Test("An empty known set never arms the settling period")
    func emptyKnownSetNeverArms() {
        #expect(
            !MenuBarItemManager.tracksMenuBarItem(bundleID: "org.freedownloadmanager.fdm6", in: [])
        )
    }

    @Test("A Control Center singleton item matches on its namespace")
    func controlCenterSingletonItemMatches() {
        // A simple "namespace:title" entry (title has no dots) still matches
        // on the namespace.
        #expect(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "com.apple.controlcenter", in: tracked)
        )
    }

    @Test("A multi-component title still matches on the namespace")
    func airBuddyWithMultiComponentTitleMatches() {
        // The title here is itself reverse-DNS shaped
        // (codes.rambo.AirBuddy.Menu); the ":" anchor must match on the
        // namespace and not be confused by the dots in the title.
        #expect(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "codes.rambo.AirBuddyHelper", in: tracked)
        )
    }
}
