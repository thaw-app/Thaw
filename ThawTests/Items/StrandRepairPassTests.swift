//
//  StrandRepairPassTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A bar the strand repair drives: each call is recorded, and a named call can seat the strand.
@MainActor
private final class FakeStrandBar: StrandRepairEnvironment {
    struct DragFailed: Error {}

    var arrangementIsManual = false
    var isBarBusy = false
    var agentIgnoresPreferredPositions = false
    var displayBounds = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    var wrappedMenuDisplay: CGDirectDisplayID?
    var bar: [MenuBarItem]
    /// The call after which the bar reads repairedBar.
    var repairingCall: String?
    var repairedBar: [MenuBarItem] = []
    /// What the bar reads after a drag that did not repair.
    var barAfterDrag: [MenuBarItem]?
    var writesSucceed = true
    var hiddenBySystem = Set<String>()
    var dragError: (any Error)?
    var onRead: () -> Void = {}
    private(set) var calls: [String] = []
    private(set) var recordedStrands: [String] = []

    init(bar: [MenuBarItem]) {
        self.bar = bar
    }

    private func note(_ call: String) -> Bool {
        calls.append(call)
        if call == repairingCall {
            bar = repairedBar
        }
        return writesSucceed
    }

    func displayWhereApplicationMenuWrapsPastNotch() -> CGDirectDisplayID? {
        wrappedMenuDisplay
    }

    func readBar() async -> [MenuBarItem] {
        calls.append("read")
        onRead()
        return bar
    }

    func isHiddenBySystemPreferences(_ item: MenuBarItem) -> Bool {
        hiddenBySystem.contains(item.uniqueIdentifier)
    }

    func moveInStore(
        _: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool, permit _: borrowing StoreWritePermit
    ) -> Bool {
        note("store")
    }

    func restoreStructuralControlOrder(controlItems _: ControlItemPair, items _: [MenuBarItem], permit _: borrowing StoreWritePermit) -> Bool {
        note("structural")
    }

    func crossClusterBoundary(
        _: [MenuBarItem], at _: MoveDestination, liveItems _: [MenuBarItem], permit _: borrowing StoreWritePermit
    ) -> Bool {
        note("cluster")
    }

    func respaceVisibleLadder(
        _ order: [String], for _: MenuBarItem, liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool, permit _: borrowing StoreWritePermit
    ) -> [String] {
        note("respace") ? order : []
    }

    func commitPreferredPositionWrite(controller _: any MenuBarSectionControlling) {
        calls.append("commit")
    }

    func waitForUserToPauseInput(timeout _: Duration) async -> Bool {
        calls.append("wait")
        return false
    }

    func move(item _: MenuBarItem, to _: MoveDestination, options _: ItemMoveOptions) async throws -> Bool {
        _ = note("move")
        if let dragError {
            throw dragError
        }
        if let barAfterDrag, repairingCall != "move" {
            bar = barAfterDrag
        }
        return false
    }

    func recordStrand(_ item: MenuBarItem) {
        recordedStrands.append(item.uniqueIdentifier)
    }

    func currentPositions() -> [String: Int] {
        [:]
    }
}

@MainActor
@Suite("Strand repair pass")
struct StrandRepairPassTests {
    private static let divider = StrandSelectionTests.hiddenDivider(x: 300)
    private let stranded = StrandSelectionTests.app("Stranded", x: 200, windowID: 1)
    private let controller = RecordingSectionController()
    private let memory = BoundaryRepairMemory()

    private var strandID: PostRestrictionRepairItemID {
        PostRestrictionRepairItemID(stranded)
    }

    private func bar(_ items: MenuBarItem...) -> [MenuBarItem] {
        items + [Self.divider, StrandSelectionTests.visibleControl]
    }

    /// A bar with the strand authored and shown as Visible, seated left of the Hidden divider.
    private func strandedBar() -> FakeStrandBar {
        controller.authoredSections[stranded.uniqueIdentifier] = .visible
        controller.itemSections[stranded.uniqueIdentifier] = .visible
        let fake = FakeStrandBar(bar: bar(stranded))
        fake.repairedBar = bar(StrandSelectionTests.app("Stranded", x: 350, windowID: 1))
        fake.barAfterDrag = bar(StrandSelectionTests.app("Stranded", x: 250, windowID: 1))
        return fake
    }

    private func run(_ fake: FakeStrandBar, whileRevealing reveal: MenuBarSectionName? = nil) async -> StrandRepairPass.Outcome {
        var repair = StrandRepairPass(
            environment: fake,
            controller: controller,
            memory: memory,
            experimentalSystemItemHiding: false,
            controlItemWindowIDs: .init(hidden: nil, alwaysHidden: nil),
            whileRevealing: reveal,
            readWeights: { StoredWeights.Table(isAvailable: false, positions: [:]) }
        )
        return await repair.run(liveItems: fake.bar, permit: StoreWritePermit.unsequenced("strand repair tests"))
    }

    @Test("Each rung writes, commits and reads the bar before the next, and the drag comes last")
    func rungOrder() async {
        let fake = strandedBar()
        let outcome = await run(fake)
        #expect(fake.calls == [
            "store", "commit", "read", "structural", "commit", "read",
            "cluster", "commit", "read", "wait", "move", "read",
        ])
        #expect(!outcome.aborted)
        #expect(outcome.strandsRemaining)
        #expect(memory.breaker.trips(for: strandID) == 1)
    }

    @Test("A write the bar confirms ends that strand's rungs")
    func confirmedWriteEndsTheRungs() async {
        let fake = strandedBar()
        fake.repairingCall = "structural"
        let outcome = await run(fake)
        #expect(fake.calls == ["store", "commit", "read", "structural", "commit", "read"])
        #expect(!outcome.aborted)
        #expect(!outcome.strandsRemaining)
    }

    @Test("A verified drag repairs the strand")
    func verifiedDrag() async {
        let fake = strandedBar()
        fake.writesSucceed = false
        fake.repairingCall = "move"
        let outcome = await run(fake)
        #expect(fake.calls == ["store", "structural", "cluster", "wait", "move", "read"])
        #expect(!outcome.strandsRemaining)
    }

    @Test("An item owed a physical seat skips the store rungs and the seat is used up")
    func mustDragSkipsTheStoreRungs() async {
        let fake = strandedBar()
        memory.pendingPhysicalSeatIDs.insert(stranded.uniqueIdentifier)
        _ = await run(fake)
        #expect(fake.calls == ["cluster", "commit", "read", "wait", "move", "read"])
        #expect(memory.pendingPhysicalSeatIDs.isEmpty)
    }

    @Test("Without preferred positions only the structural write and the drag run")
    func ignoredPositionsSkipTheirRungs() async {
        let fake = strandedBar()
        fake.agentIgnoresPreferredPositions = true
        _ = await run(fake)
        #expect(fake.calls == ["structural", "commit", "read", "wait", "move", "read"])
    }

    @Test("The visible ladder is respaced only for a strand that already failed a pass")
    func respaceOnlyAfterATrip() async {
        controller.sectionItemOrder[.visible] = [stranded.uniqueIdentifier, "com.example.Other"]
        let first = strandedBar()
        _ = await run(first)
        #expect(!first.calls.contains("respace"))

        let second = strandedBar()
        _ = await run(second)
        #expect(Array(second.calls.drop { $0 != "cluster" }) == [
            "cluster", "commit", "read", "respace", "commit", "read", "wait", "move", "read",
        ])
    }

    @Test("A one-item visible order is not respaced")
    func shortOrderIsNotRespaced() async {
        memory.breaker.addTrip(for: strandID)
        controller.sectionItemOrder[.visible] = [stranded.uniqueIdentifier]
        let fake = strandedBar()
        _ = await run(fake)
        #expect(!fake.calls.contains("respace"))
    }

    @Test("A strand that is concealed right now waits for its section instead of being dragged")
    func concealedStrandDefers() async {
        let fake = strandedBar()
        controller.itemSections[stranded.uniqueIdentifier] = .hidden
        let outcome = await run(fake)
        #expect(fake.calls.last == "read")
        #expect(!fake.calls.contains("move"))
        #expect(!fake.calls.contains("wait"))
        #expect(outcome.strandsRemaining)
    }

    @Test("Cancellation after a write aborts the pass without asking for another")
    func cancellationAborts() async {
        let fake = strandedBar()
        fake.onRead = { withUnsafeCurrentTask { $0?.cancel() } }
        let outcome = await Task { await run(fake) }.value
        #expect(fake.calls == ["store", "commit", "read"])
        #expect(outcome.aborted)
        #expect(!outcome.strandsRemaining)
    }

    @Test("Switching to Manual arrangement after a write aborts the pass")
    func manualArrangementAborts() async {
        let fake = strandedBar()
        fake.onRead = { fake.arrangementIsManual = true }
        let outcome = await run(fake)
        #expect(fake.calls == ["store", "commit", "read"])
        #expect(outcome.aborted)
    }

    @Test("A cancelled drag aborts the pass and leaves the strands for a retry")
    func cancelledDragAborts() async {
        let fake = strandedBar()
        fake.writesSucceed = false
        fake.dragError = CancellationError()
        let outcome = await run(fake)
        #expect(outcome.aborted)
        #expect(outcome.strandsRemaining)
    }

    @Test("A pass for a reveal stops before writing once that reveal has ended")
    func endedRevealAborts() async {
        let fake = strandedBar()
        let outcome = await run(fake, whileRevealing: .hidden)
        #expect(fake.calls.isEmpty)
        #expect(outcome.aborted)
        #expect(outcome.strandsRemaining)

        controller.revealedSection = .hidden
        fake.repairingCall = "store"
        let held = await run(fake, whileRevealing: .hidden)
        #expect(fake.calls == ["store", "commit", "read"])
        #expect(!held.aborted)
    }

    @Test("A failed drag that left the item where it was earns a trip, which suppresses it at the limit")
    func unmovedFailedDragIsTrapped() async {
        let fake = strandedBar()
        fake.writesSucceed = false
        fake.dragError = FakeStrandBar.DragFailed()
        let outcome = await run(fake)
        #expect(fake.calls.suffix(2) == ["move", "read"])
        #expect(fake.recordedStrands == [stranded.uniqueIdentifier])
        #expect(memory.seededStrandIDs == [strandID])
        #expect(!outcome.strandsRemaining)
    }

    @Test("The pass stops picking strands once it has spent its budget")
    func budgetStop() async {
        let strands = (0 ..< BoundaryRepairPass.strandBudget + 1).map {
            StrandSelectionTests.app("Strand\($0)", x: CGFloat(20 + 30 * $0), windowID: CGWindowID(100 + $0))
        }
        for strand in strands {
            controller.authoredSections[strand.uniqueIdentifier] = .visible
            controller.itemSections[strand.uniqueIdentifier] = .visible
        }
        let fake = FakeStrandBar(bar: strands + [Self.divider, StrandSelectionTests.visibleControl])
        fake.agentIgnoresPreferredPositions = true
        fake.writesSucceed = false
        let outcome = await run(fake)
        #expect(fake.calls.count(where: { $0 == "move" }) == BoundaryRepairPass.strandBudget)
        #expect(fake.recordedStrands.count == BoundaryRepairPass.strandBudget)
        #expect(!outcome.aborted)
    }

    @Test("An item macOS itself hides is skipped and does not ask for another pass")
    func hiddenByMacOSIsSkipped() async {
        let fake = strandedBar()
        fake.hiddenBySystem = [stranded.uniqueIdentifier]
        let outcome = await run(fake)
        #expect(fake.calls.isEmpty)
        #expect(!outcome.strandsRemaining)
    }

    @Test("A busy bar, a missing divider or a wrapped application menu ends the pass before any write")
    func passesThatNeverStart() async {
        let busy = strandedBar()
        busy.isBarBusy = true
        let blocked = await run(busy)
        #expect(blocked.aborted && !blocked.strandsRemaining)

        let noDivider = FakeStrandBar(bar: [stranded])
        let missing = await run(noDivider)
        #expect(!missing.aborted && !missing.strandsRemaining)

        let wrapped = strandedBar()
        wrapped.wrappedMenuDisplay = 2
        let declined = await run(wrapped)
        #expect(!declined.aborted && !declined.strandsRemaining)
        #expect(memory.isDecliningForWrappedMenu)
        wrapped.wrappedMenuDisplay = nil
        wrapped.repairingCall = "store"
        _ = await run(wrapped)
        #expect(!memory.isDecliningForWrappedMenu)
        #expect(busy.calls.isEmpty && noDivider.calls.isEmpty && wrapped.calls == ["store", "commit", "read"])
    }

    @Test("A Hidden divider read right of the Clock skips the pass and asks for a retry")
    func misplacedDividerAsksForARetry() async {
        let clock = MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            windowID: 20,
            ownerPID: 400,
            sourcePID: 400,
            bounds: CGRect(x: 1840, y: 3, width: 56, height: 24),
            title: "com.apple.menuextra.clock",
            isOnScreen: true
        )
        controller.authoredSections[stranded.uniqueIdentifier] = .visible
        let fake = FakeStrandBar(bar: [stranded, clock, StrandSelectionTests.hiddenDivider(x: 1860)])
        let outcome = await run(fake)
        #expect(fake.calls.isEmpty)
        #expect(!outcome.aborted && outcome.strandsRemaining)
    }

    @Test("The item manager's environment reads an idle manager without touching the store")
    func managerEnvironmentReads() {
        let environment = ItemManagerStrandRepairEnvironment(manager: MenuBarItemManager())
        #expect(!environment.arrangementIsManual)
        #expect(!environment.isBarBusy, "an idle manager is neither settling nor being arranged")
        _ = environment.agentIgnoresPreferredPositions
        _ = environment.displayWhereApplicationMenuWrapsPastNotch()
        // One rectangle per active display, each the size CoreGraphics gives that display.
        #expect(environment.displayBounds == Bridging.activeDisplayIDs().map { CGDisplayBounds($0) })
        // The line above asks CoreGraphics the way the environment does, so AppKit is asked as well:
        // its first screen is the one at the origin, whatever else is connected. CoreGraphics reports no
        // active displays while a display is asleep, so AppKit is only checked when it reports some.
        if !environment.displayBounds.isEmpty, let primary = NSScreen.screens.first {
            #expect(environment.displayBounds.contains(CGRect(origin: .zero, size: primary.frame.size)))
        }
        #expect(!environment.isHiddenBySystemPreferences(stranded))
        // The live position table belongs to the Mac running the tests, so it is not read here.
        environment.commitPreferredPositionWrite(controller: controller)
        #expect(controller.preferredPositionSelfWrites == 1, "the commit tells the section controller the write was Thaw's own")
    }
}
