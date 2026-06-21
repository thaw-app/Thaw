//
//  ProfileLayoutLogReplayTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

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
/// The Layer-1 fix excludes unresolved generic Control Center orphans from the
/// unmanaged set inside the live partitioner. Two tests pin it down:
/// testWithoutExclusionTheOrphanWouldBeUnmanaged documents the bug mechanism
/// (with no exclusion the orphan is classified unmanaged, matching the field
/// log), and testBuggyCycleDoesNotPlanMoveForUnresolvedOrphan is the regression
/// lock that fails before the fix and passes after it.
final class ProfileLayoutLogReplayTests: XCTestCase {
    private let orphanUID = "com.apple.controlcenter:Item-0"

    // MARK: Parser characterization

    /// The parser recovers both applyProfileLayout cycles and the field
    /// verdict each one logged: one unmanaged item in the buggy cycle, none
    /// in the post-resolution clean cycle.
    func testParserRecoversBothCyclesAndLoggedVerdicts() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)

        XCTAssertEqual(parsed.cycles.count, 2)
        XCTAssertTrue(
            parsed.unresolvedSourcePIDBaseUIDs.contains(orphanUID),
            "Missing sourcePID line should mark the orphan as unresolved"
        )

        let buggy = try XCTUnwrap(parsed.cycles.first)
        XCTAssertEqual(buggy.loggedUnmanagedUIDs, [orphanUID])
        XCTAssertTrue(buggy.currentVisible.contains(orphanUID))

        let clean = try XCTUnwrap(parsed.cycles.last)
        XCTAssertEqual(clean.loggedUnmanagedUIDs, [])
        XCTAssertTrue(clean.currentVisible.contains("at.obdev.littlesnitch.agent:Item-0"))
    }

    // MARK: Bug mechanism (documents what the exclusion is responsible for)

    /// With no orphan exclusion (unresolvedGenericCCUIDs empty), replaying the
    /// buggy cycle through the real partitioner reproduces the field verdict
    /// exactly: the unresolved Little Snitch orphan is the sole item routed to
    /// planUnmanagedPlacement, which is what dragged it on every cycle. The
    /// unmanaged set is reconstructed independently of the planUnmanagedPlace-
    /// ment log lines (the orphan is identified via the Missing sourcePID
    /// signal), so matching them is a genuine characterization, not a tautology.
    func testWithoutExclusionTheOrphanWouldBeUnmanaged() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let buggy = try XCTUnwrap(parsed.cycles.first)
        let inputs = buggy.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)

        XCTAssertEqual(inputs.unresolvedGenericCCOrphans, [orphanUID])

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            unresolvedGenericCCUIDs: []
        )

        XCTAssertEqual(result, buggy.loggedUnmanagedUIDs)
        XCTAssertEqual(result, [orphanUID])
    }

    // MARK: Regression lock for Layer 1 (red before the fix, green after)

    /// Replaying the buggy cycle through the live partitioner, passing the
    /// orphan set the orchestrator now computes, the unresolved Little Snitch
    /// orphan is no longer classified unmanaged, so no unmanaged placement (and
    /// therefore no move) is planned for it. This fails before Layer 1 applies
    /// unresolvedGenericCCUIDs and passes once it does.
    func testBuggyCycleDoesNotPlanMoveForUnresolvedOrphan() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let buggy = try XCTUnwrap(parsed.cycles.first)
        let inputs = buggy.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)

        // The field log confirms this orphan WAS classified unmanaged and moved.
        XCTAssertTrue(buggy.loggedUnmanagedUIDs.contains(orphanUID))
        XCTAssertEqual(inputs.unresolvedGenericCCOrphans, [orphanUID])

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            unresolvedGenericCCUIDs: inputs.unresolvedGenericCCOrphans
        )

        XCTAssertFalse(
            result.contains(orphanUID),
            "Unresolved Little Snitch orphan must not be classified unmanaged"
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Baseline: the clean cycle stays clean

    /// After marker-pair resolution the same physical item is namespaced
    /// at.obdev.littlesnitch.agent:Item-0, which the profile knows, so the
    /// unchanged partitioner already deems nothing unmanaged. This guards
    /// against a fix that over-suppresses correctly-identified items.
    func testCleanCycleHasNoUnmanagedUnderCurrentPartition() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let clean = try XCTUnwrap(parsed.cycles.last)
        let inputs = clean.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)

        XCTAssertTrue(inputs.unresolvedGenericCCOrphans.isEmpty)

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            unresolvedGenericCCUIDs: inputs.unresolvedGenericCCOrphans
        )

        XCTAssertEqual(result, clean.loggedUnmanagedUIDs)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Live wiring: control identifiers come from live tags

    /// The control identifiers the harness feeds the partitioner are derived
    /// from the live control-item tags, and they match what the field log
    /// recorded. If a control item's namespace or title changes in the Thaw
    /// codebase, this fails rather than silently diverging from real logs.
    func testLiveControlItemUIDsMatchTheFieldLog() throws {
        let parsed = ProfileLayoutLogReplay.parse(LittleSnitchOrphanLog.text)
        let buggy = try XCTUnwrap(parsed.cycles.first)

        XCTAssertEqual(
            MenuBarItemTag.alwaysHiddenControlItem.tagIdentifier,
            buggy.ahCtrlUID,
            "Live always-hidden control tag should equal the logged ahCtrlUID"
        )
        XCTAssertTrue(
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
    func testLoggedDesiredVisibleIsUsedInsteadOfInference() throws {
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
        let cycle = try XCTUnwrap(parsed.cycles.first)
        XCTAssertEqual(cycle.desiredVisible, ["com.rogueamoeba.soundsource:SSMainAppMenuIcon"])

        let inputs = cycle.partitionInputs(unresolvedSourcePIDBaseUIDs: parsed.unresolvedSourcePIDBaseUIDs)
        XCTAssertTrue(inputs.unresolvedGenericCCOrphans.isEmpty)

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: inputs.currentFlat,
            desiredUIDs: inputs.desiredUIDs,
            hiddenCtrlUID: inputs.hiddenCtrlUID,
            ahCtrlUID: inputs.ahCtrlUID,
            visibleCtrlUID: inputs.visibleCtrlUID,
            unresolvedGenericCCUIDs: inputs.unresolvedGenericCCOrphans
        )

        XCTAssertEqual(result, ["com.example.extra:Item-0"])
        XCTAssertEqual(result, cycle.loggedUnmanagedUIDs)
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
    func testDisplayReconnectNegativeBudgetYieldsNoOverflow() throws {
        let log = """
        2026-06-07 11:44:42.027 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 4 items: ["leits.MeetingBar:Item-0", "eu.exelban.Stats:CPU_bar_chart", "com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.apple.TextInputMenuAgent:Item-0"]
        2026-06-07 11:44:42.027 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 3 items: ["com.electron.dockerdesktop:Item-0", "com.apple.controlcenter:WiFi", "com.kaspersky.kav_agent:Item-0"]
        2026-06-07 11:44:42.027 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 2 items: ["ru.keepcoder.Telegram:Item-0", "com.apple.controlcenter:Battery"]
        2026-06-07 11:44:42.028 [DEBUG] [MenuBarItemManager] Notch overflow budget: screen.maxX=1728.0 notch=[771.0…956.0] rightBoundary=-222.0 availableWidth=-1202.0 userSpacing=0.0 visibleUIDs.count=14 nonProfileCount=0 nonProfileFootprint=0.0 chevronFootprint=0.0 nonProfileBreakdown=[]
        2026-06-07 11:44:42.028 [INFO] [MenuBarItemManager] Profile layout: notch overflow; 13 item(s) moved from visible to hidden
        """

        let parsed = ProfileLayoutLogReplay.parse(log)
        let cycle = try XCTUnwrap(parsed.cycles.first)

        // Field characterization: the reconnect produced an invalid (negative)
        // budget, and the buggy build ejected 13 items from visible.
        XCTAssertEqual(cycle.notchAvailableWidth, -1202)
        XCTAssertEqual(cycle.loggedOverflowCount, 13)

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

        let result = try LayoutSolver.planNotchOverflow(
            desiredFiltered: desiredFiltered,
            unmanagedUIDs: [],
            controlUIDs: ControlUIDs(visible: visibleCtrl, hidden: hiddenCtrl, alwaysHidden: ahCtrl),
            sectionMap: [:],
            uidWidths: uidWidths,
            availableWidth: XCTUnwrap(cycle.notchAvailableWidth)
        )

        XCTAssertTrue(
            result.overflowUIDs.isEmpty,
            "Negative field budget (-1202) must not eject any item once guarded; the buggy build ejected \(cycle.loggedOverflowCount ?? -1)"
        )
        XCTAssertEqual(result.updatedDesiredFiltered, desiredFiltered)
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
        /// Unresolved generic Control Center items present this cycle (nil
        /// sourcePID, Item-N title). These are what the proposed fix excludes.
        let unresolvedGenericCCOrphans: Set<String>
    }

    private static let visibleCtrlUID = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
    private static let hiddenCtrlUID = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"

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

            if let match = line.firstMatch(of: /Notch overflow budget:.*availableWidth=(-?[0-9.]+)/) {
                current?.notchAvailableWidth = Double(match.output.1).map { CGFloat($0) }
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
    /// are neither control items nor unresolved generic Control Center
    /// orphans, which is sound for those fixtures because the field log
    /// confirmed the orphan was the only visible item the profile did not
    /// cover.
    func partitionInputs(unresolvedSourcePIDBaseUIDs: Set<String>) -> ProfileLayoutLogReplay.PartitionInputs {
        // Control identifiers come from the live control-item tags, not
        // hardcoded strings, so a change to control-item identity is caught.
        let visibleCtrl = MenuBarItemTag.visibleControlItem.tagIdentifier
        let hiddenCtrl = MenuBarItemTag.hiddenControlItem.tagIdentifier
        let ahCtrl = MenuBarItemTag.alwaysHiddenControlItem.tagIdentifier

        // Live items for the current bar, per section; everything below is
        // derived from them through live Thaw code (uniqueIdentifier,
        // isControlCenterGenericItem) rather than from string heuristics.
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

        // The exact condition the Layer-1 fix will exclude: a generic Control
        // Center item (Item-N title) with no resolved source PID. Computed with
        // the live predicate so the harness tracks the production predicate.
        let orphans = Set(
            (visibleItems + hiddenItems + ahItems)
                .filter { $0.tag.isControlCenterGenericItem && $0.sourcePID == nil }
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
            unresolvedGenericCCOrphans: orphans
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
final class RelaunchSettlingGateTests: XCTestCase {
    private let tracked: Set<String> = [
        "org.freedownloadmanager.fdm6:Item-0",
        "codes.rambo.AirBuddyHelper:codes.rambo.AirBuddy.Menu",
        "com.apple.controlcenter:WiFi",
    ]

    func testTrackedAppRelaunchArmsSettling() {
        XCTAssertTrue(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "org.freedownloadmanager.fdm6", in: tracked)
        )
    }

    func testUntrackedAppLaunchDoesNotArmSettling() {
        XCTAssertFalse(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "com.apple.Safari", in: tracked)
        )
    }

    func testBundleIDPrefixBoundaryDoesNotFalseMatch() {
        // org.freedownloadmanager.fdm6 must not match a different app whose
        // bundle id merely extends it; the ":" separator anchors the match.
        let other: Set = ["org.freedownloadmanager.fdm6x:Item-0"]
        XCTAssertFalse(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "org.freedownloadmanager.fdm6", in: other)
        )
    }

    func testEmptyKnownSetNeverArms() {
        XCTAssertFalse(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "org.freedownloadmanager.fdm6", in: [])
        )
    }

    func testControlCenterSingletonItemMatches() {
        // A simple "namespace:title" entry (title has no dots) still matches
        // on the namespace.
        XCTAssertTrue(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "com.apple.controlcenter", in: tracked)
        )
    }

    func testAirBuddyWithMultiComponentTitleMatches() {
        // The title here is itself reverse-DNS shaped
        // (codes.rambo.AirBuddy.Menu); the ":" anchor must match on the
        // namespace and not be confused by the dots in the title.
        XCTAssertTrue(
            MenuBarItemManager.tracksMenuBarItem(bundleID: "codes.rambo.AirBuddyHelper", in: tracked)
        )
    }
}
