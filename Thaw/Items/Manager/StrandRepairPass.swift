//
//  StrandRepairPass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit

/// Moves visible-assigned items sitting on the hidden side of the divider back across. A re-allowed item
/// lands at its old hidden-side weight, and the pane drop could not move it while concealed. One value runs one pass.
@MainActor
struct StrandRepairPass {
    /// The refreshed live items, whether the pass was aborted (task cancelled or the reveal it belongs to
    /// ended), and whether any visible member still fails its boundary check, the retry loops' signal.
    typealias Outcome = (items: [MenuBarItem], aborted: Bool, strandsRemaining: Bool)

    /// The verdict of a repair write followed by its bar-side check. A write can
    /// report success while the bar disagrees, so the check is the truth.
    private enum BoundaryRepairVerdict: Equatable {
        case repaired
        case notRepaired
        case aborted
    }

    /// The window IDs of the Hidden and Always Hidden dividers, when they are known.
    struct ControlItemWindowIDs {
        let hidden: CGWindowID?
        let alwaysHidden: CGWindowID?
    }

    /// What the loop does after one strand's attempt.
    private enum Step {
        case nextStrand
        case endLoop
        case finish(Outcome)
    }

    private let environment: any StrandRepairEnvironment
    private let controller: any MenuBarSectionControlling
    private let memory: BoundaryRepairMemory
    private let experimentalSystemItemHiding: Bool
    private let controlItemWindowIDs: ControlItemWindowIDs
    private let revealedSection: MenuBarSectionName?
    private var selection: StrandSelection
    private var pass = BoundaryRepairPass()
    private var liveItems: [MenuBarItem] = []

    /// - Parameters:
    ///   - revealedSection: The reveal this pass answers; the pass aborts once it ends.
    ///   - readWeights: Reads the position table for the strand picks.
    init(
        environment: any StrandRepairEnvironment,
        controller: any MenuBarSectionControlling,
        memory: BoundaryRepairMemory,
        experimentalSystemItemHiding: Bool,
        controlItemWindowIDs: ControlItemWindowIDs,
        whileRevealing revealedSection: MenuBarSectionName?,
        readWeights: @escaping () -> StoredWeights.Table = { .read() }
    ) {
        self.environment = environment
        self.controller = controller
        self.memory = memory
        self.experimentalSystemItemHiding = experimentalSystemItemHiding
        self.controlItemWindowIDs = controlItemWindowIDs
        self.revealedSection = revealedSection
        selection = StrandSelection(
            memory: memory,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            authoredSection: { controller.authoredSection(for: $0) },
            readWeights: readWeights
        )
    }

    private var isInterrupted: Bool {
        environment.arrangementIsManual || Task.isCancelled
    }

    mutating func run(liveItems: [MenuBarItem], permit: borrowing StoreWritePermit) async -> Outcome {
        guard !environment.arrangementIsManual, !environment.isBarBusy, !Task.isCancelled else {
            return (liveItems, true, false)
        }
        self.liveItems = liveItems

        var itemsForControlDiscovery = liveItems
        guard let controlItems = ControlItemPair(
            items: &itemsForControlDiscovery,
            hiddenControlItemWindowID: controlItemWindowIDs.hidden,
            alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden
        ) else {
            return (liveItems, false, false)
        }

        // Every strand verdict and store write below is judged against the divider.
        // Reported as remaining, so the bounded retry tries again once the divider has settled.
        if let misplaced = ControlOrderRules.dividerMisplacement(controlItems, among: liveItems, displays: environment.displayBounds) {
            MenuBarItemManager.diagLog.debug("boundary repair: \(misplaced); skipping the pass")
            return (liveItems, false, true)
        }

        // App menus wrapping past the notch leave stale frames that read as stranded and every drag fails.
        // Skip the pass without scoring trips, since a different item strands each time.
        if let displayID = environment.displayWhereApplicationMenuWrapsPastNotch() {
            if memory.declineForWrappedMenu() {
                MenuBarItemManager.diagLog.notice(
                    "boundary repair: application menu wraps past the notch on display \(displayID); " +
                        "declining drags until it retreats"
                )
            }
            return (liveItems, false, false)
        }
        if memory.endWrappedMenuDecline() {
            MenuBarItemManager.diagLog.notice("boundary repair: application menu no longer wraps past the notch; drags re-enabled")
        }
        return await drive(from: controlItems, permit: permit)
    }

    /// Re-reads geometry after each attempt. Each strand gets one attempt per pass,
    /// but remains eligible for a later pass until verified or suppressed by the breaker.
    private mutating func drive(from dividers: ControlItemPair, permit: borrowing StoreWritePermit) async -> Outcome {
        var controlItems = dividers
        while true {
            guard let refreshed = refreshDividers(controlItems) else { return (liveItems, false, true) }
            controlItems = refreshed
            guard let strand = pass.next(in: selection.failingStrands(liveItems: liveItems, controlItems: controlItems)) else { break }
            let step = await take(strand, controlItems: controlItems, permit: permit)
            if case let .finish(outcome) = step {
                return outcome
            }
            if case .endLoop = step {
                break
            }
        }

        guard let refreshed = refreshDividers(controlItems) else { return (liveItems, false, true) }
        recordOutcomes(controlItems: refreshed)
        return (liveItems, false, pass.needsRetry(in: selection.failingStrands(liveItems: liveItems, controlItems: refreshed)))
    }

    /// After an attempt, strands are picked and judged against the divider the refreshed walk read.
    /// Nil when that walk lost the divider or misreads it, which leaves the strands for the bounded retry.
    private func refreshDividers(_ controlItems: ControlItemPair) -> ControlItemPair? {
        guard !pass.attempted.isEmpty else { return controlItems }
        return StrandSelection.refreshedDividers(
            in: liveItems,
            hiddenControlItemWindowID: controlItemWindowIDs.hidden,
            alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden,
            displays: environment.displayBounds
        )
    }

    private mutating func take(_ strand: MenuBarItem, controlItems: ControlItemPair, permit: borrowing StoreWritePermit) async -> Step {
        guard !isInterrupted else { return .finish((liveItems, true, false)) }
        guard pass.takeTurn() else {
            MenuBarItemManager.diagLog.error(pass.giveUpMessage(for: strand.logString))
            return .endLoop
        }
        if let reveal = revealedSection {
            guard !Task.isCancelled, controller.revealedSection == reveal else { return .finish((liveItems, true, true)) }
        } else {
            guard !Task.isCancelled else { return .finish((liveItems, true, true)) }
        }
        guard let destination = MenuBarLayoutPlannerProvider.current.sectionBoundaryDestination(
            for: .visible,
            controlItems: controlItems
        ) else {
            return .finish((liveItems, Task.isCancelled, false))
        }

        // Items macOS itself hides are never dragged: the host re-conceals them as the drag lands,
        // so the repair would loop on the same strand.
        if environment.isHiddenBySystemPreferences(strand) {
            MenuBarItemManager.diagLog.debug("boundary repair: \(strand.logString) is hidden by macOS; skipping")
            pass.skip(strand)
            return .nextStrand
        }

        pass.recordAttempt(strand)
        selection.forgetWeights()
        return await climb(strand, to: destination, controlItems: controlItems, permit: permit)
    }

    private mutating func climb(
        _ strand: MenuBarItem,
        to destination: MoveDestination,
        controlItems: ControlItemPair,
        permit: borrowing StoreWritePermit
    ) async -> Step {
        // Rung 1, a targeted store write judged by the bar, since a respace can report success across the
        // divider. A transitioned item skips the store rungs: only a drag teaches the agent its new slot.
        let mustDrag = memory.pendingPhysicalSeatIDs.remove(strand.uniqueIdentifier) != nil
        let storeWrote = !mustDrag && !environment.agentIgnoresPreferredPositions && environment.moveInStore(
            strand,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            permit: permit
        )
        if storeWrote, let step = await verifyBoundaryRepairAfterWrite(strand: strand, controlItems: controlItems, via: "preferred positions") {
            return step
        }

        // Rung 2, same polarity: the structural write bounds each band
        // around the divider's own weight, the targeted write's blind spot.
        var itemsForNormalize = liveItems
        if !mustDrag, let controlItemsForNormalize = ControlItemPair(
            items: &itemsForNormalize,
            hiddenControlItemWindowID: controlItemWindowIDs.hidden,
            alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden
        ), environment.restoreStructuralControlOrder(
            controlItems: controlItemsForNormalize,
            items: itemsForNormalize,
            permit: permit
        ), let step = await verifyBoundaryRepairAfterWrite(strand: strand, controlItems: controlItems, via: "structural write") {
            return step
        }

        // Rung 2.5 (needs Full Disk Access) writes the same-app cluster past the divider. It bypasses the
        // read-only wrapper, so manual mode is checked here.
        if !environment.agentIgnoresPreferredPositions, !environment.arrangementIsManual {
            let cluster = RuntimeLayoutCoordinator.sameAppCluster(of: strand, in: liveItems)
            let crossed = environment.crossClusterBoundary(cluster, at: destination, liveItems: liveItems, permit: permit)
            if crossed, let step = await verifyBoundaryRepairAfterWrite(strand: strand, controlItems: controlItems, via: "cluster crossing write") {
                return step
            }
        }

        if let step = await respaceIfTripped(strand, permit: permit) {
            return step
        }
        return await drag(strand, to: destination, controlItems: controlItems)
    }
}

extension StrandRepairPass {
    /// Rung 2.75, second pass only: once bar and weights diverge, single
    /// drags get re-sorted back, so respace the whole visible ladder.
    private mutating func respaceIfTripped(_ strand: MenuBarItem, permit: borrowing StoreWritePermit) async -> Step? {
        guard memory.breaker.trips(for: PostRestrictionRepairItemID(strand)) >= 1 else { return nil }
        let authored = controller.sectionItemOrder[.visible] ?? []
        guard authored.count > 1 else { return nil }
        let changed = environment.respaceVisibleLadder(
            authored,
            for: strand,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            permit: permit
        )
        guard !changed.isEmpty else { return nil }
        environment.commitPreferredPositionWrite(controller: controller)
        liveItems = await environment.readBar()
        guard !isInterrupted else { return .finish((liveItems, true, false)) }
        MenuBarItemManager.diagLog.info("boundary repair: rewrote the visible ladder (\(changed.count) weight(s)) for \(strand.logString)")
        return nil
    }

    /// Rung 3, the normal move pipeline without drags. A nonthrowing
    /// return can be false, so verify the strand itself. Concealed items wait.
    private mutating func drag(_ strand: MenuBarItem, to destination: MoveDestination, controlItems: ControlItemPair) async -> Step {
        if controller.section(for: strand) != .visible {
            MenuBarItemManager.diagLog.debug("boundary repair: \(strand.logString) is currently concealed; deferring move")
            return .endLoop
        }
        let inputIdle = await environment.waitForUserToPauseInput(timeout: .seconds(1.5))
        guard !isInterrupted else { return .finish((liveItems, true, false)) }
        if !inputIdle {
            MenuBarItemManager.diagLog.debug("boundary repair: user input never idled; attempting move for \(strand.logString)")
        }
        // Target the cluster's leading member, then verify the original
        // strand rather than assuming that a leader move repaired it.
        let dragItem = RuntimeLayoutCoordinator.sameAppClusterLeader(of: strand, in: liveItems) ?? strand
        if dragItem.tag != strand.tag {
            MenuBarItemManager.diagLog.info("boundary repair: moving cluster leader \(dragItem.logString) for \(strand.logString)")
        }
        do {
            let fulfilled = try await environment.move(
                item: dragItem,
                to: destination,
                options: ItemMoveOptions(skipInputPause: true, allowSectionBoundaryTarget: true)
            )
            return await judgeDrag(of: dragItem, for: strand, fulfilled: fulfilled, controlItems: controlItems)
        } catch is CancellationError {
            return .finish((liveItems, true, true))
        } catch {
            return await afterFailedDrag(of: dragItem, for: strand, error: error)
        }
    }

    private mutating func judgeDrag(
        of dragItem: MenuBarItem,
        for strand: MenuBarItem,
        fulfilled: Bool,
        controlItems: ControlItemPair
    ) async -> Step {
        liveItems = await environment.readBar()
        guard !isInterrupted else { return .finish((liveItems, true, false)) }
        if selection.satisfiesVisibleBoundary(items: liveItems, item: strand, controlItems: controlItems) {
            MenuBarItemManager.diagLog.info("Repaired macOS 27 visible boundary for \(strand.logString) via verified move")
            return .nextStrand
        }
        // A move can decline without throwing, so an unchanged frame on the wrong side earns the same
        // extra trip as an error; movement alone is not proof of repair.
        if StrandSelection.unmovedAfterDrag(dragItem, in: liveItems) != nil {
            memory.breaker.addTrip(for: PostRestrictionRepairItemID(strand))
        }
        MenuBarItemManager.diagLog.info("boundary repair: \(strand.logString) remains stranded after move (fulfilled=\(fulfilled))")
        return .nextStrand
    }

    private mutating func afterFailedDrag(of dragItem: MenuBarItem, for strand: MenuBarItem, error: any Error) async -> Step {
        guard !isInterrupted else { return .finish((liveItems, true, false)) }
        MenuBarItemManager.diagLog.error("macOS 27 visible boundary repair failed for \(strand.logString): \(error)")
        // A drag that leaves the frame where it was grabbed a trapped or
        // bounced item; more drags will not change that, so it retires.
        liveItems = await environment.readBar()
        guard !isInterrupted else { return .finish((liveItems, true, false)) }
        if let after = StrandSelection.unmovedAfterDrag(dragItem, in: liveItems) {
            memory.breaker.addTrip(for: PostRestrictionRepairItemID(strand))
            MenuBarItemManager.diagLog.info("boundary repair: \(strand.logString) never moved (x=\(Int(after.bounds.minX))); trapped or bounced")
        }
        return .endLoop
    }

    /// Commits a repair write, waits for MenuBarAgent to re-sort, and re-checks the strand's boundary.
    /// Nil when the bar still disagrees, so the next rung runs.
    private mutating func verifyBoundaryRepairAfterWrite(
        strand: MenuBarItem,
        controlItems: ControlItemPair,
        via label: String
    ) async -> Step? {
        switch await verdictAfterWrite(strand: strand, controlItems: controlItems, via: label) {
        case .aborted: .finish((liveItems, true, false))
        case .repaired: .nextStrand
        case .notRepaired: nil
        }
    }

    private mutating func verdictAfterWrite(strand: MenuBarItem, controlItems: ControlItemPair, via label: String) async -> BoundaryRepairVerdict {
        environment.commitPreferredPositionWrite(controller: controller)
        liveItems = await environment.readBar()
        guard !isInterrupted else { return .aborted }
        if selection.satisfiesVisibleBoundary(items: liveItems, item: strand, controlItems: controlItems) {
            MenuBarItemManager.diagLog.info("Repaired macOS 27 visible boundary for \(strand.logString) via \(label)")
            return .repaired
        }
        return .notRepaired
    }

    /// A repaired item's history is cleared; one still stranded after
    /// BoundaryRepairMemory.tripLimit consecutive passes is suppressed until its cooldown ends.
    private func recordOutcomes(controlItems: ControlItemPair) {
        guard !isInterrupted else { return }
        for suppression in selection.scoreOutcomes(attempted: pass.attempted, liveItems: liveItems, controlItems: controlItems) {
            let strand = suppression.strand
            environment.recordStrand(strand)
            MenuBarItemManager.diagLog.error(
                "post-restriction repair: suppressing boundary repair for persistently stranded " +
                    "\(strand.logString) after \(suppression.trips) passes " +
                    "\(strandDiagnostics(for: strand, controlItems: controlItems)) " +
                    ", check RuntimePositionStore.applyOrder re-seat"
            )
        }
    }

    /// Reads the position table only when the suppression line is logged.
    private func strandDiagnostics(for strand: MenuBarItem, controlItems: ControlItemPair) -> String {
        let positions = environment.currentPositions()
        let weights = StoredWeights(among: liveItems, table: StoredWeights.Table(isAvailable: true, positions: positions))
        return StrandSelection.strandDiagnostics(
            for: strand, hiddenDivider: controlItems.hidden, positions: positions, weight: { weights.weight(of: $0) }
        )
    }
}
