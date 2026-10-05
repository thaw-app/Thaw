//
//  MenuBarItemManager+Moving.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit

// MARK: - Moving Items

extension MenuBarItemManager {
    typealias MoveDestination = MenuBarModel.MoveDestination
}

extension MenuBarItemManager {
    /// The opening guess for an unknown item; apps differ tenfold in how fast
    /// they open a menu, so each item learns its own.
    private static let defaultClickOperationTimeout: Duration = .milliseconds(350)

    func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        clickOperationTimeouts[item.tag] ?? Self.defaultClickOperationTimeout
    }

    /// Moves the estimate halfway toward each observation, clamped so fast runs
    /// cannot starve a slow day and one outlier cannot make clicks feel broken.
    func updateClickOperationTimeout(_ duration: Duration, for item: MenuBarItem) {
        let blended = (duration + getClickOperationTimeout(for: item)) / 2
        let clamped = blended.clamped(min: .milliseconds(200), max: .milliseconds(1000))
        clickOperationTimeouts[item.tag] = clamped
        MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(duration.milliseconds))ms)")
    }

    /// Keeps the estimates from growing without bound over a long session.
    func pruneClickOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickOperationTimeouts = clickOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// The live bar without position-store recoveries, whose inferred frames
    /// have nothing under them for a drag to grab.
    static func dragGeometry(from items: [MenuBarItem]) -> [MenuBarItem] {
        let recovered = PositionStoreItemSource.recoveredTags
        return items.filter { !recovered.contains($0.tag) }
    }

    /// Whether the item is stuck at the x = -1 sentinel macOS uses for
    /// unplaced items. Unreadable bounds count as not blocked.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try await getCurrentBounds(for: item)
            return bounds.origin.x == -1
        } catch {
            return false
        }
    }

    /// Resolves the destination against the live bar: the anchor, then the
    /// alternates captured at drop time, since the anchor can quit or rotate
    /// its window ID. The first one present wins, rewritten to the live item.
    ///
    /// Nil rather than a throw, since the store write addresses the anchor by
    /// key and only the drag needs a live frame.
    static nonisolated func resolvedDestination(
        for destination: MoveDestination,
        fallbacks: [MoveDestination],
        item: MenuBarItem,
        among livePeers: [MenuBarItem]
    ) -> MoveDestination? {
        let chain = [destination] + fallbacks
        for (index, candidate) in chain.enumerated() {
            guard
                let liveAnchor = livePeers.first(where: {
                    !$0.isSystemClone && !$0.isNativeOverflowControl && $0.hasSameIdentity(as: candidate.targetItem)
                })
            else {
                continue
            }
            let resolved: MoveDestination = switch candidate {
            case .leftOfItem: .leftOfItem(liveAnchor)
            case .rightOfItem: .rightOfItem(liveAnchor)
            }
            if index > 0 {
                MenuBarItemManager.diagLog.warning(
                    "Anchor \(destination.targetItem.logString) vanished mid-drop; " +
                        "resolved \(item.logString) against alternate \(resolved.targetItem.logString)"
                )
            } else if resolved != destination {
                MenuBarItemManager.diagLog.debug(
                    "Anchor \(destination.targetItem.logString) rotated during rescan mid-drop; " +
                        "re-resolved against live geometry"
                )
            }
            return resolved
        }
        return nil
    }

    private static func targetsAlwaysHiddenDivider(_ destination: MoveDestination) -> Bool {
        destination.targetItem.tag == .alwaysHiddenControlItem
    }

    /// Validates that an item moved to the hidden section didn't get stuck at x=-1.
    /// If the item is blocked, attempts to restore it to the visible section.
    private func validateItemPositionAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID?
    ) async {
        // Recover only an unplaced item, or a move aimed at the hidden divider,
        // so a correct move is left alone.
        let isUnplaced = await isItemBlocked(item)
        guard Self.targetsAlwaysHiddenDivider(destination) || isUnplaced else { return }

        if isUnplaced {
            MenuBarItemManager.diagLog.warning("Item \(item.logString) stuck at x=-1 after move - attempting recovery")
            guard let appState else { return }

            // An unseated control item cannot be moved; only re-registering it
            // seats a fresh window.
            if await republishUnseatedControlItem(item) {
                if await waitForControlReSeat(item) {
                    markControlItemSeated(item, in: appState)
                } else {
                    MenuBarItemManager.diagLog.error(
                        "Re-published \(item.logString) but the window never seated; skipping the move retry"
                    )
                    return
                }
            }

            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let anchor = Self.recoveryAnchor(
                stuck: item,
                items: items,
                hiddenControlItemWindowNumber: appState.menuBarManager.controlItem(withName: .hidden)?.window?.windowNumber,
                section: { appState.menuBarManager.sectionController.section(for: $0) }
            )
            guard let anchor else {
                MenuBarItemManager.diagLog.error(
                    "Cannot recover item: no seated anchor on the bar for \(item.logString)"
                )
                return
            }
            if anchor.tag != .hiddenControlItem {
                MenuBarItemManager.diagLog.warning(
                    "Hidden control item is not seated; recovering \(item.logString) right of \(anchor.logString)"
                )
            }

            do {
                try await move(
                    item: item,
                    to: .rightOfItem(anchor),
                    on: displayID,
                    skipInputPause: true,
                    allowParkedOffMenuBarSource: true,
                    recoveringUnplacedItem: true
                )
                MenuBarItemManager.diagLog.info("Successfully recovered \(item.logString) from blocked state to visible section")
            } catch {
                MenuBarItemManager.diagLog.error("Failed to recover \(item.logString) from blocked state: \(error)")
            }
        }
    }

    /// Restores the re-publish budget of the control item behind item after
    /// a re-registered window provably seated.
    private func markControlItemSeated(_ item: MenuBarItem, in appState: AppState) {
        guard let name = Self.controlItemSectionName(for: item.tag) else { return }
        appState.menuBarManager.controlItem(withName: name)?.markSeated()
    }

    /// Prefers the hidden control item. macOS 27 does not order the
    /// zero-length window of an empty Hidden section, so the fallback is the
    /// rightmost seated visible item other than the stuck one.
    static nonisolated func recoveryAnchor(
        stuck: MenuBarItem,
        items: [MenuBarItem],
        hiddenControlItemWindowNumber: Int?,
        section: (MenuBarItem) -> MenuBarSection.Name?
    ) -> MenuBarItem? {
        if let hiddenControlItemWindowNumber,
           let windowID = CGWindowID(exactly: hiddenControlItemWindowNumber),
           let seated = items.first(where: { $0.windowID == windowID })
        {
            return seated
        }
        return items
            .filter { candidate in
                candidate.windowID != stuck.windowID
                    && candidate.tag != .hiddenControlItem
                    && candidate.tag != .alwaysHiddenControlItem
                    && section(candidate) == .visible
                    && candidate.bounds.minX >= 0
                    && candidate.bounds.width > 0
            }
            .max { $0.bounds.maxX < $1.bounds.maxX }
    }

    /// Re-registers the status item behind item when the item names one of
    /// Thaw's control items, returning whether a re-publish happened.
    private func republishUnseatedControlItem(_ item: MenuBarItem) async -> Bool {
        guard let appState,
              let name = Self.controlItemSectionName(for: item.tag),
              let controlItem = appState.menuBarManager.controlItem(withName: name)
        else {
            return false
        }
        guard case .republish = controlItem.republishIfUnseated() else {
            return false
        }
        return true
    }

    static nonisolated func controlItemSectionName(for tag: MenuBarItemTag) -> MenuBarSection.Name? {
        switch tag {
        case .visibleControlItem: .visible
        case .hiddenControlItem: .hidden
        case .alwaysHiddenControlItem: .alwaysHidden
        default: nil
        }
    }

    /// Waits for a re-published control item to hold a real seat, up to about
    /// a second.
    private func waitForControlReSeat(_ item: MenuBarItem) async -> Bool {
        for _ in 0 ..< 20 {
            try? await Task.sleep(for: .milliseconds(50))
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            if let fresh = items.first(where: { $0.tag == item.tag }), await !isItemBlocked(fresh) {
                MenuBarItemManager.diagLog.info(
                    "Re-published \(item.logString) seated at \(NSStringFromRect(fresh.bounds))"
                )
                return true
            }
        }
        return false
    }

    /// Puts item beside the destination item. Most of this is refusal: an
    /// unchanged bar is always a better failure than a wrong one.
    ///
    /// The silent position-preference write goes first; the synthetic ⌘-drag,
    /// which takes the cursor, only when the write cannot express the move.
    /// A move neither can express is left undone and retried later.
    ///
    /// - Parameters:
    ///   - item: The item to move.
    ///   - destination: Where it should end up, relative to another item.
    ///   - anchorFallbacks: Alternates captured beside the anchor at planning
    ///     time, tried in order if it vanished.
    /// - Returns: Whether the item is now at destination.
    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        allowSectionBoundaryTarget: Bool = false,
        allowParkedOffMenuBarSource: Bool = false,
        anchorFallbacks: [MoveDestination] = [],
        isUserInitiated: Bool = false,
        recoveringUnplacedItem: Bool = false,
        allowSyntheticDrag: Bool = true
    ) async throws -> Bool {
        if !skipInputPause {
            guard await waitForUserToPauseInput(timeout: nil) else { throw CancellationError() }
        }
        let fulfilled = try await withMenuBarMutation(isUserInitiated: isUserInitiated) {
            try await moveWhileHoldingMutation(
                item: item,
                to: destination,
                on: displayID,
                allowSectionBoundaryTarget: allowSectionBoundaryTarget,
                allowParkedOffMenuBarSource: allowParkedOffMenuBarSource,
                anchorFallbacks: anchorFallbacks,
                isUserInitiated: isUserInitiated,
                allowSyntheticDrag: allowSyntheticDrag
            )
        }
        // A window the host never laid out reports failure by construction, so only a
        // failed move or one aimed at the hidden divider is worth the AX walk that checks.
        // Nothing to check under the lock screen; a recovery move would be refused too.
        if !recoveringUnplacedItem, !screenLockTransitions.isLocked,
           !fulfilled || Self.targetsAlwaysHiddenDivider(destination)
        {
            await validateItemPositionAfterMove(item: item, destination: destination, on: displayID)
        }
        return fulfilled
    }

    private func withMenuBarMutation<Result: Sendable>(
        isUserInitiated: Bool,
        _ operation: () async throws -> Result
    ) async throws -> Result {
        var awaitingUserMove = isUserInitiated
        if isUserInitiated {
            cancelPendingSectionOrderApply()
            structuralNormalizationTask?.cancel()
            structuralNormalizationTask = nil
            pendingUserReorderCount += 1
        }
        defer {
            if awaitingUserMove {
                pendingUserReorderCount -= 1
            }
        }
        let result = try await moveSerialSemaphore.withPermit {
            if awaitingUserMove {
                pendingUserReorderCount -= 1
                awaitingUserMove = false
            }
            layoutPublication.beginMutation()
            defer { layoutPublication.endMutation() }
            return try await operation()
        }
        // A successful user mutation is the user's retry, so clear the breaker.
        // Boxed through Any because section transitions return Void.
        if isUserInitiated, (result as Any) as? Bool == true {
            moveCircuitBreaker.noteUserOverride()
        }
        return result
    }

    /// Only called inside withMenuBarMutation; section transitions reuse
    /// their existing permit instead of queueing behind themselves.
    private func moveWhileHoldingMutation(
        item: MenuBarItem,
        to destination: MoveDestination,
        transitionSection: MenuBarSection.Name? = nil,
        on displayID: CGDirectDisplayID? = nil,
        allowSectionBoundaryTarget: Bool = false,
        allowParkedOffMenuBarSource: Bool = false,
        anchorFallbacks: [MoveDestination] = [],
        isUserInitiated: Bool = false,
        allowSyntheticDrag: Bool = true
    ) async throws -> Bool {
        if let refusal = moveRefusal(
            item: item,
            destination: destination,
            isUserInitiated: isUserInitiated,
            allowSectionBoundaryTarget: allowSectionBoundaryTarget
        ) {
            switch refusal {
            case .unfulfilled:
                return false
            case let .throwError(error):
                throw error
            }
        }
        var moveFulfilled = false
        defer {
            if moveFulfilled, !Task.isCancelled, Self.shouldNormalizeStructureAfterMove(
                item: item,
                destination: destination,
                isUserInitiated: isUserInitiated
            ) {
                scheduleStructuralNormalization()
            }
        }
        guard let appState else {
            throw EventError.cannotComplete
        }
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding

        let geometryStarted = ContinuousClock.now
        let priorityPIDs = Set(([item, destination.targetItem] + anchorFallbacks.map(\.targetItem)).flatMap {
            [$0.ownerPID, $0.sourcePID].compactMap(\.self)
        })
        guard let livePeers = await MenuBarItem.getFreshMenuBarItemsForMove(priorityPIDs: priorityPIDs) else {
            MenuBarItemManager.diagLog.warning("Move geometry unavailable; preserving the requested order")
            throw EventError.cannotComplete
        }
        try Task.checkCancellation()
        MenuBarItemManager.diagLog.debug("Move geometry: \(ContinuousClock.now - geometryStarted)")

        // x == -1 means not placed yet. A user's drag is often the fix, so only
        // automatic passes are refused, except in the rescue direction.
        if (try? Self.currentBounds(for: item, among: livePeers))?.origin.x == -1 {
            let rescueDirection = switch destination {
            case .rightOfItem: true
            default: item.tag.matchesVisibleControlItem
            }
            let allowsBlockedMove = isUserInitiated || rescueDirection
            guard allowsBlockedMove else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        // Same for the reflow's parking band: automatic passes leave it alone,
        // the user's drag unparks it.
        if !allowParkedOffMenuBarSource,
           !isUserInitiated,
           item.isParkedOffMenuBarBand(among: livePeers)
        {
            MenuBarItemManager.diagLog.warning(
                "Skipping move for \(item.logString) - item is parked off the menu bar band"
            )
            throw EventError.cannotComplete
        }
        if isUserInitiated, item.isParkedOffMenuBarBand(among: livePeers) {
            MenuBarItemManager.diagLog.debug(
                "Proceeding with move of parked \(item.logString); the user's drop is the unpark"
            )
        }

        // An unresolved anchor is not a refusal yet: the store write names it
        // by key. Only the drag path, which needs geometry, fails on it.
        let liveDestination = Self.resolvedDestination(
            for: destination,
            fallbacks: anchorFallbacks,
            item: item,
            among: livePeers
        )
        let destination = liveDestination ?? destination

        let resolvedDisplayID: CGDirectDisplayID = if let displayID {
            displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            window.displayID
        } else {
            Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        try await waitForMoveOperationBuffer()

        // Pauses the image cache's live loop, whose AX walks would queue ahead
        // of this move's and slow them roughly tenfold.
        moveActivity.beginMoveOperation()
        defer { moveActivity.endMoveOperation() }

        MenuBarItemManager.diagLog.info(
            """
            Moving \(item.logString) to \
            \(destination.logString) on display \(resolvedDisplayID)
            """
        )

        // One walk serves the already-there check, the store write and the
        // first drag. The check uses the drag's own relative-order predicate.
        let liveItems = livePeers
        if MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesDestination(
            items: liveItems,
            item: item,
            destination: destination,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) {
            MenuBarItemManager.diagLog.debug("\(item.logString) is already at \(destination.logString); nothing to do")
            moveFulfilled = true
            return true
        }
        // A write counts only after fresh AX verification.
        if try await moveItemViaPreferredPositions(
            item: item,
            to: destination,
            transitionSection: transitionSection,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            isUserInitiated: isUserInitiated
        ) {
            moveMonitor.recordStoreMove(
                item: item.logString,
                destination: destination.logString,
                satisfied: true
            )
            moveFulfilled = true
            return true
        }

        // Drag only with live geometry at both ends; a concealed anchor would
        // drop the icon blind, so that move waits for the reveal. Opted-in
        // section transitions are exempt: the drag re-resolves the collapsed
        // divider mid-gesture.
        let targetIsUsable = allowSectionBoundaryTarget
            || (destination.targetItem.isOnScreen && !destination.targetItem.bounds.isEmpty)
        let canDragSynthetically = item.isOnScreen && !item.bounds.isEmpty
            && targetIsUsable
        guard canDragSynthetically else {
            // No anchor on the bar is a fact about the bar, not the item; the
            // unpark path relies on this to avoid a persisted "won't move" verdict.
            if liveDestination == nil {
                throw EventError.destinationAnchorLost(item)
            }
            MenuBarItemManager.diagLog.info(
                "Position-only reorder could not fulfill \(item.logString) \(destination.logString)"
            )
            return false
        }
        // The conceal assertion completes a section-boundary move, so where
        // the agent ignores preferred positions a drag would only take the cursor.
        if destination.targetItem.tag.matchesSectionBoundaryControlItem,
           menuBarAgentIgnoresPreferredPositions
        {
            MenuBarItemManager.diagLog.info(
                "Section-boundary move of \(item.logString) left to the conceal assertion; " +
                    "the agent ignores preferred positions, so the drag would only take the cursor"
            )
            return false
        }

        // A user move falls through to the Command-drag after a store decline.
        // Background passes never take the cursor, and callers may refuse the drag.
        guard allowSyntheticDrag else {
            MenuBarItemManager.diagLog.debug(
                "Position-only move of \(item.logString): the caller refused the synthetic drag"
            )
            return false
        }
        if isUserInitiated {
            guard await waitForUserToPauseInput(timeout: .seconds(1.5)) else {
                try Task.checkCancellation()
                return false
            }
            Self.diagLog.info("preferred-position move declined; trying one Command-drag for \(item.logString)")
            try await moveItemViaCommandDrag(
                item: item,
                to: destination,
                maxAttempts: 1,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
            moveFulfilled = true
            return true
        }
        MenuBarItemManager.diagLog.info(
            "Position write declined \(item.logString) \(destination.logString); synthetic drag disabled"
        )
        return false
    }

    /// unfulfilled returns false; throwError carries an error the caller must see.
    private enum MoveRefusal {
        case unfulfilled
        case throwError(EventError)
    }

    /// Refusal checks, in the order they must run. Manual arrangement refuses
    /// every move but an explicit Layout edit here, before the normalization defer. Lock screen, clones,
    /// the native chevron and store recoveries are no-ops; the rest throw so
    /// the caller knows.
    private func moveRefusal(
        item: MenuBarItem,
        destination: MoveDestination,
        isUserInitiated: Bool,
        allowSectionBoundaryTarget: Bool
    ) -> MoveRefusal? {
        guard !arrangementForbidsMoves else {
            MenuBarItemManager.diagLog.debug(
                "Refusing move of \(item.logString): manual arrangement is on"
            )
            return .unfulfilled
        }

        // A move under the lock screen lands on a layout the unlock replaces. A
        // no-op false is the one outcome no caller persists as a verdict.
        if refuseMenuBarMutationWhileScreenLocked("move of \(item.logString)") {
            return .unfulfilled
        }

        // Runaway guard. A user's own move always goes through, even while the
        // breaker is open: it is one deliberate action, not a storm, and it is
        // how the user retries. Automatic passes stop.
        if moveCircuitBreaker.isOpen, !isUserInitiated {
            MenuBarItemManager.diagLog.debug(
                "Move circuit breaker open; skipping automatic move of \(item.logString)"
            )
            return .unfulfilled
        }
        if moveCircuitBreaker.isOpen, isUserInitiated {
            MenuBarItemManager.diagLog.info(
                "Move circuit breaker open; allowing the user's move of \(item.logString)"
            )
        }

        // Backstop for transient system clones: dragging one displaces real
        // items, and it vanishes on its own, so a no-op is correct.
        guard !item.isSystemClone else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - system status item clone")
            return .unfulfilled
        }
        // The native chevron has no window to grab and no weight the agent honours.
        guard !item.isNativeOverflowControl, !destination.targetItem.isNativeOverflowControl else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - native overflow control")
            return .unfulfilled
        }
        // A store recovery is a preference key with a synthetic window ID:
        // nothing to grab, and only an invented frame to verify against.
        if PositionStoreItemSource.recoveredTags.contains(item.tag) {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - position-store recovery")
            return .unfulfilled
        }
        guard let appState else {
            return .throwError(EventError.cannotComplete)
        }
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding
        guard item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) else {
            return .throwError(EventError.itemNotMovable(
                item,
                item.orderabilityRefusal(experimentalSystemItemHiding: experimentalSystemItemHiding)
            ))
        }

        // Never move during a user ⌘-drag: overlapping drags strand or
        // duplicate icons and can crash Finder. The drop re-runs this work later.
        if appState.isDraggingMenuBarItem {
            MenuBarItemManager.diagLog.info("Skipping move for \(item.logString) - user ⌘-drag in progress")
            return .throwError(EventError.cannotComplete)
        }

        // A drag at a hung owner only times out. ownerPID is the compositing
        // host from macOS 26, so sourcePID is asked first.
        let ownerPID = item.sourcePID ?? item.ownerPID
        if ownerPID != ProcessInfo.processInfo.processIdentifier {
            if Bridging.isProcessUnresponsive(ownerPID) {
                if unresponsiveMoveOwners.insert(ownerPID).inserted {
                    MenuBarItemManager.diagLog.warning(
                        "Refusing move of \(item.logString): owner pid \(ownerPID) is not responding; " +
                            "further moves of its items are refused until it answers"
                    )
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "Refusing move of \(item.logString): owner pid \(ownerPID) is still not responding"
                    )
                }
                return .throwError(EventError.itemResponseTimeout(item))
            }
            if unresponsiveMoveOwners.remove(ownerPID) != nil {
                MenuBarItemManager.diagLog.info("Owner pid \(ownerPID) is responding again; moving its items resumes")
            }
        }

        // Legacy divider targets relied on a reflow macOS 27 no longer does.
        // Section transitions opt in, using the divider as a visible drag anchor.
        if !allowSectionBoundaryTarget {
            let target = destination.targetItem
            if target.isControlItem,
               target.tag != .visibleControlItem
            {
                MenuBarItemManager.diagLog.warning(
                    "Skipping legacy divider hide-move of \(item.logString) to \(destination.logString) on macOS 27"
                )
                return .unfulfilled
            }
        }
        return nil
    }

    /// Called every cache tick while locked, so only transitions are logged.
    func refuseMenuBarMutationWhileScreenLocked(_ refused: String) -> Bool {
        let locked = ScreenLock.isLocked
        if screenLockTransitions.update(locked) {
            if locked {
                MenuBarItemManager.diagLog.info(
                    "Screen is locked; refusing \(refused) and every menu bar move until it unlocks"
                )
            } else {
                MenuBarItemManager.diagLog.info("Screen unlocked; menu bar moves resume")
            }
        }
        return locked
    }

    /// Re-runs the structural weight write once activity settles. Only it sees
    /// every section, so it pins the settled order as contiguous bands (the
    /// agent never persists ⌘-drags as weights). Idempotent once in sync.
    func scheduleStructuralNormalization(
        after: Duration = .milliseconds(800),
        deferralsRemaining: Int = 8
    ) {
        structuralNormalizationTask?.cancel()
        structuralNormalizationTask = nil
        guard !isInStartupSettling, !moveCircuitBreaker.isOpen,
              !isNotificationCenterLayoutSuspended
        else { return }
        structuralNormalizationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: after)
            guard !Task.isCancelled, let self else { return }
            structuralNormalizationTask = nil
            guard let appState,
                  !appState.isDraggingMenuBarItem,
                  !isInStartupSettling,
                  !isApplyingProfileLayout
            else { return }
            // Manual arrangement turns this off, except to re-lay a stranded
            // visible control item, which the user cannot drag back.
            let manualAllowsControlRelay: Bool = {
                guard arrangementIsManual else { return true }
                let settled = itemCache.managedItems
                return !settled.isEmpty && Self.visibleControlIsStranded(among: settled)
            }()
            guard manualAllowsControlRelay else {
                MenuBarItemManager.diagLog.debug("structural normalization: skipping, manual arrangement is on")
                return
            }
            // During a reveal the writes would flicker the bar, so re-arm a
            // bounded number of times instead of dropping the work.
            guard layoutPublication.canPublish(generation: layoutPublication.generation),
                  appState.menuBarManager.sectionController.revealedSection == nil,
                  !appState.menuBarManager.isRevealHideTransitionActive
            else {
                if deferralsRemaining > 0 {
                    scheduleStructuralNormalization(
                        after: after,
                        deferralsRemaining: deferralsRemaining - 1
                    )
                }
                return
            }

            // Wait out the move cooldown rather than skip, or a burst of drags
            // would keep the normalization from ever running. Bounded.
            var settleWaits = 0
            while lastMoveOperationOccurred(within: .seconds(1)),
                  !Task.isCancelled,
                  settleWaits < 15
            {
                try? await Task.sleep(for: .milliseconds(400))
                settleWaits += 1
            }
            guard !Task.isCancelled else { return }
            guard layoutPublication.canPublish(generation: layoutPublication.generation) else {
                if deferralsRemaining > 0 {
                    scheduleStructuralNormalization(after: after, deferralsRemaining: deferralsRemaining - 1)
                }
                return
            }

            // The debounce and settle waits can span a screen lock.
            guard !refuseMenuBarMutationWhileScreenLocked("structural normalization") else { return }

            // The cache, not a fresh walk: the walk omits concealed members,
            // whose stale weights would then sit inside the new visible band.
            let settledItems = itemCache.managedItems
            guard !settledItems.isEmpty else { return }
            if !arrangementIsManual, !menuBarAgentIgnoresPreferredPositions,
               Self.trailingSiriIsMisplaced(in: settledItems) {
                // Siri needs one row repaired; no dividers required, which
                // managedItems omits.
                _ = moveCircuitBreaker.note(.storeWrite)
                let changed = RuntimePositionStore.repairTrailingSiri(liveItems: settledItems)
                if !changed.isEmpty {
                    appState.menuBarManager.sectionController.notePreferredPositionsSelfWrite()
                    moveActivity.noteMoveOperation()
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    await cacheItemsRegardless(skipRecentMoveCheck: true)
                }
                return
            }
            guard let controlItems = controlItemPair(in: settledItems) else { return }

            if restoreStructuralControlOrder(controlItems: controlItems, items: settledItems) {
                moveActivity.noteMoveOperation()
            }

            // Respace concealed bands while invisible, so the host's remembered
            // slots make the next reveal expand in authored order.
            if !arrangementIsManual, !menuBarAgentIgnoresPreferredPositions {
                let sectionController = appState.menuBarManager.sectionController
                for section in MenuBarSection.Name.allCases where section != .visible {
                    let desiredOrder = sectionController.sectionItemOrder[section] ?? []
                    guard desiredOrder.count > 1 else { continue }
                    let members = desiredOrder.compactMap { identifier in
                        settledItems.first { $0.uniqueIdentifier == identifier }
                    }
                    guard members.count > 1 else { continue }
                    guard !refuseMenuBarMutationWhileScreenLocked("concealed-band normalization") else { return }
                    let trace = tracePositionWrite(
                        context: "normalization respace \(section.logString)",
                        items: settledItems,
                        desiredOrder: members.map(\.uniqueIdentifier)
                    )
                    _ = moveCircuitBreaker.note(.storeWrite)
                    let changed = MenuBarPositionStoreProvider.current.respaceOrder(
                        desiredOrder: members.map(\.uniqueIdentifier),
                        liveItems: settledItems,
                        experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding,
                        // A volatile-title item (a live clock) must not veto
                        // this, or every reveal re-interleaves the band through
                        // the visible lane and overflows into the chevron.
                        mayRewriteAroundUnplaceableItems: true
                    )
                    trace?.finish(result: String(describing: changed))
                    if !changed.isEmpty {
                        MenuBarItemManager.diagLog.info(
                            "normalization: re-spaced \(changed.count) concealed \(section.logString) weight(s)"
                        )
                    }
                }
                // Sibling icons sharing a weight swap places between passes, so
                // state their rendered order explicitly.
                guard !refuseMenuBarMutationWhileScreenLocked("sibling-weight normalization") else { return }
                _ = moveCircuitBreaker.note(.storeWrite)
                let separated = MenuBarPositionStoreProvider.current.breakTiedSiblingWeights(
                    liveItems: settledItems
                )
                if !separated.isEmpty {
                    MenuBarItemManager.diagLog.info(
                        "normalization: separated \(separated.count) tied sibling weight(s)"
                    )
                }
                requestMenuBarAgentPositionRefresh()
                moveActivity.noteMoveOperation()
            }

            guard !refuseMenuBarMutationWhileScreenLocked("native visibility normalization") else { return }

            // Native Always-Hidden writes other apps' preferences, so it sits
            // behind its own switch; off restores every recorded key.
            if !Defaults.bool(forKey: .useNativeAlwaysHide) {
                NativeAlwaysHide.restoreRecordedStates()
            } else if !appState.menuBarManager.nativeAppHidingExperiment.isActive {
                NativeAlwaysHide.reconcile(
                    items: settledItems,
                    assignedAlwaysHiddenIdentifiers: Set(
                        appState.menuBarManager.sectionController.sectionItemOrder[.alwaysHidden] ?? []
                    )
                )
            }
        }
    }

    // MARK: macOS 27 Command-drag move

    /// Whether the System Settings toggle hides this item (NSStatusItem
    /// VisibleCC <label> = false). Such items are never ordered: the host
    /// re-conceals them and repair would drag ghosts. Fails open.
    static func isHiddenBySystemPreferences(_ item: MenuBarItem) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: item.ownerPID),
              let bundleID = app.bundleIdentifier
        else { return false }
        let domain = bundleID as CFString
        for key in ["NSStatusItem VisibleCC \(item.tag.title)", "NSStatusItem Visible \(item.tag.title)"] {
            if let flag = CFPreferencesCopyAppValue(key as CFString, domain) as? Bool, !flag {
                return true
            }
        }
        return false
    }

    private static var loggedSystemHiddenItems: Set<String> = []

    /// Applies the saved order before the restriction is released, so the bar
    /// reveals straight into it without moving Thaw's click target.
    func applySavedOrderBeforeReveal() {
        guard appState != nil
        else {
            return
        }

        let cachedItems = itemCache.managedItems
        let controlItemWindowIDs = liveControlItemWindowIDs()
        let discoveredControlItems = controlItemPair(in: cachedItems)
        let controlItems: ControlItemPair
        if let discoveredControlItems {
            controlItems = discoveredControlItems
        } else {
            // Collapsed dividers have no AX element on macOS 27; the store
            // resolves these synthetic stand-ins by tag and title.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let leadingX = itemCache.displayID.map { CGDisplayBounds($0).minX }
                ?? (NSScreen.main?.frame.minX ?? 0)
            let hidden = MenuBarItem(
                tag: .hiddenControlItem,
                windowID: controlItemWindowIDs.hidden ?? 0,
                ownerPID: ourPID,
                sourcePID: ourPID,
                bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                title: ControlItem.Identifier.hidden.rawValue,
                isOnScreen: false
            )
            let alwaysHidden: MenuBarItem? = if configuration.isAlwaysHiddenSectionEnabled {
                MenuBarItem(
                    tag: .alwaysHiddenControlItem,
                    windowID: controlItemWindowIDs.alwaysHidden ?? 0,
                    ownerPID: ourPID,
                    sourcePID: ourPID,
                    bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                    title: ControlItem.Identifier.alwaysHidden.rawValue,
                    isOnScreen: false
                )
            } else {
                nil
            }
            controlItems = ControlItemPair(
                hidden: hidden,
                alwaysHidden: alwaysHidden
            )
        }

        if !arrangementIsManual,
           restoreStructuralControlOrder(
               controlItems: controlItems,
               items: cachedItems,
               diagnosticContext: "pre-reveal cached restore"
           )
        {
            MenuBarItemManager.diagLog.info(
                "macOS 27: prepared cached structural order before reveal"
            )
        }
    }

    /// Restores the persisted order after a reveal with the batch store write,
    /// not the per-item boundary loop, which flashes icons through
    /// intermediate orders. The agent re-allows items at remembered slots
    /// regardless of weight, so the loop still runs if members end up stranded.
    func synchronizeRevealedOrder(
        revealing revealedSection: MenuBarSection.Name
    ) async {
        // Manual arrangement owns the order: a reveal shows the items where
        // the user last dragged them, and no structural write may re-seat
        // anything.
        guard !arrangementIsManual else {
            MenuBarItemManager.diagLog.debug("synchronizeRevealedOrder: skipping, manual arrangement is on")
            return
        }
        // A re-seat during or right after a ⌘-drag undoes the drop before its
        // sections are read.
        guard !isUserArrangingMenuBar else {
            MenuBarItemManager.diagLog.debug("synchronizeRevealedOrder: skipping, the user is arranging the menu bar")
            return
        }
        // With the store inert the batch write does nothing; repair with drags.
        if menuBarAgentIgnoresPreferredPositions {
            await reconcileSectionBoundaries(revealing: revealedSection)
            return
        }

        guard let appState,
              appState.menuBarManager.sectionController.revealedSection == revealedSection
        else {
            return
        }

        let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !Task.isCancelled,
              appState.menuBarManager.sectionController.revealedSection == revealedSection
        else {
            return
        }
        let controlItemWindowIDs = liveControlItemWindowIDs()
        // Mid-reveal the walk can miss members not yet re-allowed, and laddering
        // a partial run scrambles the bar. Complete it from the cache; the
        // strand check still reads the live walk.
        let structuralItems = Self.completingPartialWalk(liveItems, with: itemCache.managedItems)
        if structuralItems.count != liveItems.count {
            MenuBarItemManager.diagLog.debug(
                "synchronizeRevealedOrder: live walk holds \(liveItems.count) item(s); " +
                    "completed \(structuralItems.count - liveItems.count) from the cache for the structural write"
            )
        }
        guard let controlItems = controlItemPair(in: structuralItems) else {
            MenuBarItemManager.diagLog.debug(
                "synchronizeRevealedOrder: control items not ready"
            )
            return
        }

        // With the dividers already in order the batch write would only
        // re-lay weights, which the host animates.
        let visibleControl = structuralItems.first { $0.tag.matchesVisibleControlItem }
        if let visibleControl,
           Self.controlTrioInCanonicalOrder(
               alwaysHidden: controlItems.alwaysHidden,
               hidden: controlItems.hidden,
               visible: visibleControl
           )
        {
            MenuBarItemManager.diagLog.debug(
                "synchronizeRevealedOrder: AH | H | V already in order; skipping structural rewrite"
            )
        } else {
            let restored = await enforceControlItemOrder(
                controlItems: controlItems,
                items: structuralItems,
                reason: .revealedLayoutRestore
            )
            if !restored {
                MenuBarItemManager.diagLog.debug(
                    "synchronizeRevealedOrder: live order already matches saved layout"
                )
            }
        }

        // The agent ignores the new weight when re-allowing an item, so verify
        // against the bar once the reflow settles.
        let controller = appState.menuBarManager.sectionController
        let experimentalSystemItemHiding = appState.settings.advanced
            .enableExperimentalSystemItemHiding
        let stranded: ([MenuBarItem]) -> [MenuBarItem] = { items in
            var discovery = items
            guard let pair = ControlItemPair(
                items: &discovery,
                hiddenControlItemWindowID: controlItemWindowIDs.hidden,
                alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden
            ) else {
                return []
            }
            return Self.membersStrandedAcrossDivider(
                items: items,
                controlItems: pair,
                sectionFor: { controller.section(for: $0) },
                experimentalSystemItemHiding: experimentalSystemItemHiding,
                isRepairSuppressed: {
                    self.suppressedBoundaryRepairItemIDs.contains(
                        self.postRestrictionRepairItemID(for: $0)
                    )
                }
            )
        }
        let wait = await waitForMenuBarAgentLayout(
            deadline: ContinuousClock.now + Self.revealStrandSettleBudget,
            isSatisfied: { stranded($0).isEmpty }
        )
        guard !wait.cancelled, !Task.isCancelled,
              controller.revealedSection == revealedSection
        else {
            return
        }
        let remaining = stranded(wait.items)
        guard remaining.isEmpty else {
            MenuBarItemManager.diagLog.info(
                "synchronizeRevealedOrder: \(remaining.count) member(s) re-seated across the divider " +
                    "after reveal (\(remaining.map(\.logString).joined(separator: ", "))); repairing physically"
            )
            // The reconcile applies the revealed sections' authored order
            // itself once the boundary holds.
            await reconcileSectionBoundaries(revealing: revealedSection)
            return
        }
        await applyAuthoredOrderForRevealedSections(
            revealedSection,
            controller: controller,
            liveItems: wait.items
        )
    }

    /// Brings revealed sections to their authored order, or the hidden order
    /// would drift on every show and hide. Drags only while the bar disagrees.
    private func applyAuthoredOrderForRevealedSections(
        _ revealedSection: MenuBarSection.Name,
        controller: any MenuBarSectionControlling,
        liveItems: [MenuBarItem]
    ) async {
        let sections: [MenuBarSection.Name] = switch revealedSection {
        case .alwaysHidden: [.hidden, .alwaysHidden]
        case .hidden, .visible: [.hidden]
        }
        var liveItems = liveItems
        for attempt in 1 ... Self.authoredVisibleOrderApplyAttempts {
            let disagreeing = sections.filter { section in
                let authored = controller.sectionItemOrder[section] ?? []
                return authored.count > 1 &&
                    !liveOrderMatches(authored, section: section, controller: controller, items: liveItems)
            }
            guard !disagreeing.isEmpty else { return }
            guard !Task.isCancelled, controller.revealedSection == revealedSection else { return }
            MenuBarItemManager.diagLog.info(
                "macOS 27: applying authored \(disagreeing.map(\.logString).joined(separator: "+")) " +
                    "order physically on reveal (attempt \(attempt))"
            )
            await applySectionItemOrder(
                sections: disagreeing,
                controller: controller,
                whileRevealing: revealedSection,
                reason: .revealRestore
            )
            guard !Task.isCancelled else { return }
            liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        }
    }

    /// How long a reveal may reflow before its result is judged.
    private static let revealStrandSettleBudget: Duration = .milliseconds(1500)

    /// Live items on the wrong side of the hidden divider for their section.
    /// Items no move could fix never count.
    static nonisolated func membersStrandedAcrossDivider(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        sectionFor: (MenuBarItem) -> MenuBarSection.Name,
        experimentalSystemItemHiding: Bool,
        isRepairSuppressed: (MenuBarItem) -> Bool = { _ in false }
    ) -> [MenuBarItem] {
        items.filter { item in
            guard !item.isControlItem, !item.isSystemClone, !item.isNativeOverflowControl else { return false }
            // An item the repair ladder has given up on cannot be moved by any
            // weight, so repairing it here only re-seats its neighbours, and it
            // strands again on the next reveal.
            guard !isRepairSuppressed(item) else { return false }
            return !MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                items: items,
                item: item,
                section: sectionFor(item),
                controlItems: controlItems,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        }
    }

    /// Whether a suppressed boundary repair still holds. With no timestamp it
    /// holds until cleared, matching the strand pass, which only reads the set.
    static nonisolated func boundaryRepairIsSuppressed(
        suppressedAt: Date?,
        now: Date,
        cooldown: TimeInterval
    ) -> Bool {
        guard let suppressedAt else { return true }
        return now.timeIntervalSince(suppressedAt) < cooldown
    }

    /// Counts consecutive failures. A repair or reaching tripLimit (which also
    /// suppresses) resets it; nil trips removes the entry.
    static nonisolated func boundaryRepairBreakerStep(
        priorTrips: Int,
        repaired: Bool,
        tripLimit: Int
    ) -> (trips: Int?, suppress: Bool) {
        guard !repaired else { return (nil, false) }
        let trips = priorTrips + 1
        guard trips >= tripLimit else { return (trips, false) }
        return (nil, true)
    }

    /// Scores one reveal-time section boundary repair against the breaker the
    /// visible-strand pass uses.
    private func recordSectionBoundaryRepairOutcome(for item: MenuBarItem, repaired: Bool) {
        let id = postRestrictionRepairItemID(for: item)
        let step = Self.boundaryRepairBreakerStep(
            priorTrips: boundaryRepairStrandTrips[id] ?? 0,
            repaired: repaired,
            tripLimit: Self.boundaryRepairTripLimit
        )
        boundaryRepairStrandTrips[id] = step.trips
        guard step.suppress else { return }
        suppressedBoundaryRepairItemIDs.insert(id)
        suppressedBoundaryRepairAt[id] = Date()
        MenuBarItemManager.diagLog.warning(
            "macOS 27 section boundary repair: suppressing \(item.logString) after " +
                "\(Self.boundaryRepairTripLimit) failed reveals for " +
                "\(Int(Self.boundaryRepairSuppressionCooldown)) s"
        )
    }

    /// Repairs assignments written by earlier macOS 27 builds that concealed
    /// items without first moving them across a real divider. Runs only while a
    /// hidden section is revealed, because concealed items have no AX elements.
    func reconcileSectionBoundaries(
        revealing revealedSection: MenuBarSection.Name
    ) async {
        // Manual arrangement owns the order: boundary repairs are automatic
        // reordering, which the user explicitly declined.
        guard !arrangementIsManual else {
            MenuBarItemManager.diagLog.debug("reconcileSectionBoundaries: skipping, manual arrangement is on")
            return
        }
        guard !isUserArrangingMenuBar else {
            MenuBarItemManager.diagLog.debug("reconcileSectionBoundaries: skipping, the user is arranging the menu bar")
            return
        }
        guard let appState else { return }
        let controller = appState.menuBarManager.sectionController
        guard !Task.isCancelled, controller.revealedSection == revealedSection else { return }

        // The divider was just republished for this reveal; fix the boundary
        // before moving items around it.
        var liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !Task.isCancelled, controller.revealedSection == revealedSection else { return }
        let controlItemWindowIDs = liveControlItemWindowIDs()
        var itemsForControlDiscovery = liveItems
        if let controlItems = ControlItemPair(
            items: &itemsForControlDiscovery,
            hiddenControlItemWindowID: controlItemWindowIDs.hidden,
            alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden
        ) {
            await enforceControlItemOrder(
                controlItems: controlItems,
                items: liveItems,
                reason: .explicitLayoutRepair
            )
            // Re-walk only if a divider move was planned.
            if MenuBarLayoutPlannerProvider.current.dividerMoveDestination(
                items: liveItems,
                sectionAssignment: controller.sectionAssignment,
                controlItems: controlItems,
                experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding
            ) != nil {
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }
        }

        // Include .visible: an item re-allowed at a hidden-side slot with no
        // weight of its own is moved back nowhere else.
        let sectionsToReconcile: Set<MenuBarSection.Name> = switch revealedSection {
        case .visible, .hidden:
            [.hidden, .visible]
        case .alwaysHidden:
            [.hidden, .alwaysHidden, .visible]
        }
        let assignments = controller.sectionAssignment
            .filter { sectionsToReconcile.contains($0.value) }
            .sorted { lhs, rhs in lhs.key < rhs.key }
        let experimentalSystemItemHiding = appState.settings.advanced
            .enableExperimentalSystemItemHiding

        for (identifier, section) in assignments {
            guard !Task.isCancelled,
                  controller.revealedSection == revealedSection
            else {
                return
            }

            guard let liveItem = liveItems.first(where: {
                $0.uniqueIdentifier == identifier
            }) else {
                continue
            }

            var itemsForControlDiscovery = liveItems
            guard let controlItems = ControlItemPair(
                items: &itemsForControlDiscovery,
                hiddenControlItemWindowID: controlItemWindowIDs.hidden,
                alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden
            ),
                !MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                    items: liveItems,
                    item: liveItem,
                    section: section,
                    controlItems: controlItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                ),
                let destination = MenuBarLayoutPlannerProvider.current.sectionBoundaryDestination(
                    for: section,
                    controlItems: controlItems
                )
            else {
                continue
            }

            // Runs on every reveal, so it shares the strand pass's breaker and
            // re-arms. The cooldown is checked here because those re-arms only
            // run on a restriction change.
            let repairID = postRestrictionRepairItemID(for: liveItem)
            if suppressedBoundaryRepairItemIDs.contains(repairID) {
                if Self.boundaryRepairIsSuppressed(
                    suppressedAt: suppressedBoundaryRepairAt[repairID],
                    now: Date(),
                    cooldown: Self.boundaryRepairSuppressionCooldown
                ) {
                    MenuBarItemManager.diagLog.debug(
                        "macOS 27 section boundary repair skipped for \(liveItem.logString): suppressed"
                    )
                    continue
                }
                suppressedBoundaryRepairItemIDs.remove(repairID)
                suppressedBoundaryRepairAt[repairID] = nil
                boundaryRepairStrandTrips[repairID] = nil
            }

            // The ordinary move: a verified store write, then a drag, since the
            // agent ignores the row for a re-allowed item.
            var repaired = false
            do {
                let moved = try await move(
                    item: liveItem,
                    to: destination,
                    skipInputPause: true,
                    allowSectionBoundaryTarget: true
                )
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                // A re-hide mid-move leaves nothing to judge; no strike.
                guard !Task.isCancelled, controller.revealedSection == revealedSection else { return }
                // A move can report success while the agent re-seats the item,
                // so the bar decides the strike, as in the strand pass.
                var refreshedForControlDiscovery = liveItems
                if moved,
                   let refreshed = liveItems.first(where: { $0.uniqueIdentifier == identifier }),
                   let refreshedControlItems = ControlItemPair(
                       items: &refreshedForControlDiscovery,
                       hiddenControlItemWindowID: controlItemWindowIDs.hidden,
                       alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden
                   )
                {
                    repaired = MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                        items: liveItems,
                        item: refreshed,
                        section: section,
                        controlItems: refreshedControlItems,
                        experimentalSystemItemHiding: experimentalSystemItemHiding
                    )
                }
                if repaired {
                    MenuBarItemManager.diagLog.info(
                        "Repaired macOS 27 section boundary for \(liveItem.logString)"
                    )
                } else if moved {
                    MenuBarItemManager.diagLog.info(
                        "macOS 27 section boundary repair: \(liveItem.logString) still across the divider after move"
                    )
                } else {
                    MenuBarItemManager.diagLog.warning(
                        "macOS 27 section boundary repair declined for \(liveItem.logString) \(destination.logString)"
                    )
                }
            } catch {
                // hideRevealedSections() cancels this task on re-hide, so a
                // cancellation ends the pass rather than failing the repair.
                if error is CancellationError || Task.isCancelled {
                    MenuBarItemManager.diagLog.debug(
                        "macOS 27 section boundary repair for \(liveItem.logString) cancelled by re-hide"
                    )
                    return
                }
                MenuBarItemManager.diagLog.error(
                    "macOS 27 section boundary repair failed for \(liveItem.logString): \(error)"
                )
            }
            recordSectionBoundaryRepairOutcome(for: liveItem, repaired: repaired)
        }

        // Visible is expressed by absence from sectionAssignment, so the loop
        // above never sees visible items re-seated on the hidden side.
        let strand = await repairVisibleItemsSeatedAmongHidden(
            liveItems: liveItems,
            controller: controller,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            hiddenControlItemWindowID: controlItemWindowIDs.hidden,
            alwaysHiddenControlItemWindowID: controlItemWindowIDs.alwaysHidden,
            whileRevealing: revealedSection
        )
        if strand.aborted {
            return
        }
        liveItems = strand.items

        var sectionsToOrder: [MenuBarSection.Name] = switch revealedSection {
        case .visible, .hidden: [.hidden]
        case .alwaysHidden: [.hidden, .alwaysHidden]
        }
        if authoredVisibleOrderPendingPhysicalApply {
            // A pending pane edit: without this, an item moved into visible
            // stays at its old hidden-side slot for the whole reveal.
            sectionsToOrder.append(.visible)
        }
        await applySectionItemOrder(
            sections: sectionsToOrder,
            controller: controller,
            whileRevealing: revealedSection,
            // nil uses the controller's authored order: with an edit pending,
            // the mirrored savedSectionOrder may predate it.
            visibleOrderOverride: nil,
            reason: .revealRestore
        )
        if sectionsToOrder.contains(.visible) {
            // Retire the edit only once the bar shows it, or the next cache
            // pass would mirror the old order over it.
            let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let desiredOrder = (controller.sectionItemOrder[.visible] ?? [])
                .filter { controller.section(for: $0) == .visible }
            if desiredOrder.isEmpty || liveOrderMatches(
                desiredOrder,
                section: .visible,
                controller: controller,
                items: liveItems
            ) {
                authoredVisibleOrderPendingPhysicalApply = false
            } else {
                MenuBarItemManager.diagLog.info(
                    "Reveal ordering left the authored visible order unrealized; keeping it pending"
                )
            }
        }

        await cacheItemsRegardless(skipRecentMoveCheck: true)
    }

    /// Writes the items' weights into the new section's band before the
    /// assertion changes their section, since MenuBarAgent republishes an item
    /// at its existing weight. Safe while concealed: weight is only order.
    ///
    /// The first item anchors on the boundary and the rest chain off it, so a
    /// group keeps its order instead of stacking into one slot.
    ///
    /// The weight is only a hint: an item leaving the visible bar is also
    /// dragged across the divider here; one arriving from a concealed section
    /// is dragged by the strand pass. The commit runs under the same permit,
    /// so the next drop never starts from an uncommitted assignment.
    @MainActor
    func seatItemsForSectionTransition(
        _ items: [MenuBarItem],
        to section: MenuBarSection.Name,
        orderedAs order: [MenuBarItem]? = nil,
        commit: () -> Void
    ) async {
        // In Manual only an explicit Layout edit, which seats the item itself, may change a section.
        // Thaw Bar Only items are exempt: macOS never draws them.
        if arrangementForbidsMoves, !items.allSatisfy(isThawBarOnly) {
            MenuBarItemManager.diagLog.info(
                "Section transition to \(section.logString) refused: manual arrangement is on"
            )
            appState?.layoutFeedback.post(LayoutBarFeedbackCenter.manualSectionChange())
            await cacheItemsRegardless(skipRecentMoveCheck: true)
            return
        }
        do {
            try await withMenuBarMutation(isUserInitiated: true) {
                if items.allSatisfy({
                    MenuBarBackendProvider.current.canAssign(
                        $0,
                        to: section,
                        experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding
                    )
                }) {
                    await seatItemsWhileHoldingMutation(items, to: section, orderedAs: order)
                }
                try Task.checkCancellation()
                commit()
            }
        } catch is CancellationError {
            MenuBarItemManager.diagLog.debug("Section transition cancelled before assignment commit")
        } catch {
            MenuBarItemManager.diagLog.error("Section transition failed: \(error)")
        }
    }

    private func seatItemsWhileHoldingMutation(
        _ items: [MenuBarItem],
        to section: MenuBarSection.Name,
        orderedAs order: [MenuBarItem]? = nil
    ) async {
        let movedIdentifiers = Set(items.map(\.uniqueIdentifier))
        var seatedIdentifiers = Set<String>()
        var previous: MenuBarItem?
        for item in items {
            // The authored predecessor seats a mid-band drop in place on the
            // first draw, not at the band edge.
            let authored = Self.authoredPredecessor(
                of: item,
                in: order,
                excluding: movedIdentifiers.subtracting(seatedIdentifiers)
            )
            let seated = seatItemForSectionTransition(
                item,
                to: section,
                after: authored ?? previous
            )
            if seated {
                seatedIdentifiers.insert(item.uniqueIdentifier)
                previous = item
            }
        }

        guard section != .visible else {
            for item in items {
                pendingPhysicalSeatIDs.insert(item.uniqueIdentifier)
            }
            return
        }

        var previousDragged: MenuBarItem?
        for item in items where item.isOnScreen && !item.bounds.isEmpty {
            guard !Task.isCancelled else { return }
            guard let destination = sectionTransitionDestination(
                for: section,
                after: previousDragged
            ) else {
                MenuBarItemManager.diagLog.warning(
                    "No divider to drag \(item.logString) behind before concealment"
                )
                break
            }
            do {
                // Position-only: the conceal assertion hides these items
                // whether or not the write lands, so a synthetic drag would
                // only move the user's cursor for nothing.
                if try await moveWhileHoldingMutation(
                    item: item,
                    to: destination,
                    transitionSection: section,
                    allowSectionBoundaryTarget: true,
                    isUserInitiated: true,
                    allowSyntheticDrag: false
                ) {
                    previousDragged = item
                    MenuBarItemManager.diagLog.info(
                        "Dragged \(item.logString) into the \(section.logString) band before concealment"
                    )
                } else {
                    MenuBarItemManager.diagLog.warning(
                        "Pre-concealment drag declined for \(item.logString) \(destination.logString)"
                    )
                }
            } catch {
                MenuBarItemManager.diagLog.error(
                    "Pre-concealment drag failed for \(item.logString): \(error)"
                )
            }
        }
    }

    /// The item immediately before item in an authored order, skipping the
    /// ones moving with it that are not yet seated, or nil when it is first.
    static func authoredPredecessor(
        of item: MenuBarItem,
        in order: [MenuBarItem]?,
        excluding movedIdentifiers: Set<String>
    ) -> MenuBarItem? {
        guard
            let order,
            let index = order.firstIndex(where: { $0.uniqueIdentifier == item.uniqueIdentifier })
        else { return nil }
        return order[..<index].last { !movedIdentifiers.contains($0.uniqueIdentifier) }
    }

    /// Where an item joining section goes: behind predecessor when one was
    /// just seated (so a group keeps its arrangement), else at the section's
    /// band boundary beside the relevant divider.
    @MainActor
    private func sectionTransitionDestination(
        for section: MenuBarSection.Name,
        after predecessor: MenuBarItem?
    ) -> MoveDestination? {
        guard let controlItems = lastKnownControlItems else { return nil }
        let bandBoundary: MoveDestination = switch section {
        case .visible:
            .rightOfItem(controlItems.hidden)
        case .hidden:
            if configuration.isAlwaysHiddenSectionEnabled == true,
               let alwaysHidden = controlItems.alwaysHidden
            {
                .rightOfItem(alwaysHidden)
            } else {
                .leftOfItem(controlItems.hidden)
            }
        case .alwaysHidden:
            if let alwaysHidden = controlItems.alwaysHidden {
                .leftOfItem(alwaysHidden)
            } else {
                .leftOfItem(controlItems.hidden)
            }
        }
        return predecessor.map { .rightOfItem($0) } ?? bandBoundary
    }

    @discardableResult
    @MainActor
    private func seatItemForSectionTransition(
        _ item: MenuBarItem,
        to section: MenuBarSection.Name,
        after predecessor: MenuBarItem? = nil
    ) -> Bool {
        guard let appState, let controlItems = lastKnownControlItems,
              let destination = sectionTransitionDestination(for: section, after: predecessor)
        else { return false }
        var liveItems = managedItems
        liveItems.append(controlItems.hidden)
        if let alwaysHidden = controlItems.alwaysHidden {
            liveItems.append(alwaysHidden)
        }
        guard MenuBarPositionStoreProvider.forLayoutEdit.move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding
        ) else {
            MenuBarItemManager.diagLog.debug(
                "No pre-seat written for \(item.logString) into \(section.logString)"
            )
            return false
        }
        commitPreferredPositionWrite(controller: appState.menuBarManager.sectionController)
        MenuBarItemManager.diagLog.info(
            "Pre-seated \(item.logString) into the \(section.logString) band before the section change"
        )
        return true
    }

    /// Whether a persisted namespace:title identifier names an item macOS
    /// pins, mirroring MenuBarItemTag.isNonConcealableSystemItem for the
    /// case where only the identifier is in hand.
    static nonisolated func namesPinnedSystemItem(_ identifier: String) -> Bool {
        identifier.hasPrefix("com.apple.")
    }

    /// Whether the live bar already realizes desiredOrder for section, so the
    /// edit apply can tell a pass that worked from one that placed nothing.
    @MainActor
    func liveOrderMatches(
        _ desiredOrder: [String],
        section: MenuBarSection.Name,
        controller: any MenuBarSectionControlling,
        items: [MenuBarItem]
    ) -> Bool {
        let sectionItems = items.filter {
            MenuBarLayoutPlannerProvider.current.isEligibleForSectionOrder($0, section: section) &&
                controller.section(for: $0) == section
        }
        return MenuBarLayoutPlannerProvider.current.nextAchievableOrderMove(
            items: sectionItems,
            desiredOrder: desiredOrder,
            experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding
        ) == nil
    }

    /// Re-gathers the visible order around current groups and writes it, so a
    /// new group closes up on the bar too. Fixed anchors split the order into
    /// segments, so an impossible cross-anchor move cannot loop. Concealed
    /// sections are applied on their next reveal.
    @MainActor
    func applyGroupOrderToLiveSections() async {
        guard let controller = appState?.menuBarManager.sectionController
        else {
            return
        }
        // Re-commit so the order reflects the group set that just changed;
        // gathering runs inside the commit. A no-op commit writes nothing.
        controller.regatherGroups()
        // A group-set change is an edit the user just committed.
        await applySectionItemOrder(sections: [.visible], controller: controller, reason: .userReorder)

        // A permutation can leave other apps' weights between a group's
        // members. Respacing rewrites the segment, so only when interleaved.
        let desiredOrder = (controller.sectionItemOrder[.visible] ?? [])
            .filter { controller.section(for: $0) == .visible }
        if desiredOrder.count > 1,
           !menuBarAgentIgnoresPreferredPositions,
           isAnyGroupInterleaved(in: desiredOrder)
        {
            let liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let respaced = MenuBarPositionStoreProvider.current.respaceOrder(
                desiredOrder: desiredOrder,
                liveItems: liveItems,
                experimentalSystemItemHiding: configuration.enableExperimentalSystemItemHiding,
                // A group edit is an explicit request; see the interleaved-
                // unplaceable note in the structural normalization above.
                mayRewriteAroundUnplaceableItems: true
            )
            if !respaced.isEmpty {
                commitPreferredPositionWrite(controller: controller)
            }
        }

        await cacheItemsRegardless(skipRecentMoveCheck: true)
    }

    /// Moves visible-assigned items sitting on the hidden side of the divider
    /// back across. A re-allowed item lands at its old hidden-side weight, and
    /// the pane drop could not move it while concealed.
    ///
    /// - Returns: The refreshed live items, whether the pass was aborted (task
    ///   cancelled or the reveal it belongs to ended), and whether any visible
    ///   member still fails its boundary check after the attempts, the retry
    ///   loops' signal.
    func repairVisibleItemsSeatedAmongHidden(
        liveItems: [MenuBarItem],
        controller: any MenuBarSectionControlling,
        experimentalSystemItemHiding: Bool,
        hiddenControlItemWindowID: CGWindowID?,
        alwaysHiddenControlItemWindowID: CGWindowID?,
        whileRevealing revealedSection: MenuBarSection.Name?
    ) async -> (items: [MenuBarItem], aborted: Bool, strandsRemaining: Bool) {
        guard !arrangementIsManual, !isInStartupSettling, !isUserArrangingMenuBar, !Task.isCancelled else {
            return (liveItems, true, false)
        }
        var liveItems = liveItems
        var pass = BoundaryRepairPass()

        var itemsForControlDiscovery = liveItems
        guard let controlItems = ControlItemPair(
            items: &itemsForControlDiscovery,
            hiddenControlItemWindowID: hiddenControlItemWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
        ) else {
            return (liveItems, false, false)
        }

        // When app menus wrap past the notch, evicted items leave stale frames
        // that read as stranded and every drag fails. Skip the pass, scoring no
        // trips, since a different item strands each time.
        if let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main,
           MenuBarCapacitySnapshot.applicationMenuWrapsPastNotch(on: screen)
        {
            if !isBoundaryRepairDeclinedForWrappedMenu {
                isBoundaryRepairDeclinedForWrappedMenu = true
                MenuBarItemManager.diagLog.notice(
                    "boundary repair: application menu wraps past the notch on display \(screen.displayID); " +
                        "declining drags until it retreats"
                )
            }
            return (liveItems, false, false)
        }
        if isBoundaryRepairDeclinedForWrappedMenu {
            isBoundaryRepairDeclinedForWrappedMenu = false
            MenuBarItemManager.diagLog.notice(
                "boundary repair: application menu no longer wraps past the notch; drags re-enabled"
            )
        }

        // A phantom frame is a seat something else already occupies; dragging
        // from it grabs that other item. Logged once per pass per item.
        var loggedPhantomIDs = Set<String>()
        func isPhantomStrand(_ item: MenuBarItem) -> Bool {
            guard item.hasPhantomFrame(among: liveItems) else { return false }
            if loggedPhantomIDs.insert(item.uniqueIdentifier).inserted {
                // Name the occupant: a seat held by a second window of the same
                // app needs a different fix from one held by another app.
                let seatHolders = liveItems
                    .filter { $0.windowID != item.windowID }
                    .filter {
                        abs($0.bounds.minX - item.bounds.minX)
                            < MenuBarItemGeometry.phantomFrameXTolerance
                    }
                    .map(\.logString)
                MenuBarItemManager.diagLog.debug(
                    "boundary repair: \(item.logString) has a phantom frame " +
                        "(x=\(Int(item.bounds.minX)) occupied by " +
                        "\(seatHolders.isEmpty ? "an overlapping neighbour" : seatHolders.joined(separator: ", "))); " +
                        "not draggable"
                )
            }
            return true
        }

        func failingStrands() -> [MenuBarItem] {
            liveItems.filter { item in
                !item.isControlItem &&
                    !item.isSystemClone &&
                    !item.isNativeOverflowControl &&
                    !isPhantomStrand(item) &&
                    !suppressedBoundaryRepairItemIDs.contains(
                        postRestrictionRepairItemID(for: item)
                    ) &&
                    item.isPhysicallyOrderable(
                        experimentalSystemItemHiding: experimentalSystemItemHiding
                    ) &&
                    controller.authoredSection(for: item.uniqueIdentifier) == .visible &&
                    (
                        // A pane transition owes a drag whatever the check
                        // says: with the section collapsed the concealed
                        // neighbours the item stands among are invisible to it.
                        pendingPhysicalSeatIDs.contains(item.uniqueIdentifier) ||
                            !MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                                items: liveItems,
                                item: item,
                                section: .visible,
                                controlItems: controlItems,
                                experimentalSystemItemHiding: experimentalSystemItemHiding
                            )
                    )
            }
        }

        // Re-read geometry after each attempt. Each strand gets one attempt
        // per pass, but remains eligible for a later pass until verified or
        // suppressed by the breaker.
        var iterations = 0
        while let strand = pass.next(in: failingStrands()) {
            guard !arrangementIsManual, !Task.isCancelled else { return (liveItems, true, false) }
            iterations += 1
            if iterations > 6 {
                MenuBarItemManager.diagLog.error(
                    "macOS 27 visible boundary repair gave up after \(iterations) strands for \(strand.logString)"
                )
                break
            }
            if let reveal = revealedSection {
                guard !Task.isCancelled,
                      controller.revealedSection == reveal
                else {
                    return (liveItems, true, true)
                }
            } else {
                guard !Task.isCancelled else { return (liveItems, true, true) }
            }
            guard let destination = MenuBarLayoutPlannerProvider.current.sectionBoundaryDestination(
                for: .visible,
                controlItems: controlItems
            ) else {
                return (liveItems, Task.isCancelled, false)
            }

            // Items macOS itself hides are never dragged: the host
            // re-conceals them the moment a drag lands, so the move cannot
            // verify and the repair would iterate the same strand forever.
            if Self.isHiddenBySystemPreferences(strand) {
                MenuBarItemManager.diagLog.debug(
                    "boundary repair: \(strand.logString) is hidden by macOS; skipping"
                )
                continue
            }

            pass.recordAttempt(strand)
            // Rung 1, targeted store write, judged by the bar: a respace can
            // report success while straddling the divider. True means the item
            // is on the correct side; negating it would loop forever.
            // A transitioned item skips the store rungs; only a drag teaches
            // the agent its new slot.
            let mustDrag = pendingPhysicalSeatIDs.remove(strand.uniqueIdentifier) != nil
            if !mustDrag,
               !menuBarAgentIgnoresPreferredPositions,
               MenuBarPositionStoreProvider.current.move(
                   item: strand,
                   to: destination,
                   liveItems: liveItems,
                   experimentalSystemItemHiding: experimentalSystemItemHiding
               )
            {
                let verify = await verifyBoundaryRepairAfterWrite(
                    strand: strand,
                    controller: controller,
                    controlItems: controlItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding,
                    via: "preferred positions"
                )
                liveItems = verify.items
                if verify.verdict == .aborted {
                    return (verify.items, true, false)
                }
                if verify.verdict == .repaired {
                    continue
                }
            }

            // Rung 2, same polarity: the structural write bounds each band
            // around the divider's own weight, the targeted write's blind spot.
            var itemsForNormalize = liveItems
            if !mustDrag, let controlItemsForNormalize = ControlItemPair(
                items: &itemsForNormalize,
                hiddenControlItemWindowID: hiddenControlItemWindowID,
                alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWindowID
            ), restoreStructuralControlOrder(
                controlItems: controlItemsForNormalize,
                items: itemsForNormalize
            ) {
                let verify = await verifyBoundaryRepairAfterWrite(
                    strand: strand,
                    controller: controller,
                    controlItems: controlItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding,
                    via: "structural write"
                )
                liveItems = verify.items
                if verify.verdict == .aborted {
                    return (verify.items, true, false)
                }
                if verify.verdict == .repaired {
                    continue
                }
            }

            // Rung 2.5 (needs Full Disk Access): write the whole same-app
            // cluster past the divider, which rungs 1 and 2 refuse to split.
            // It bypasses the read-only wrapper, so manual mode is checked here.
            if !menuBarAgentIgnoresPreferredPositions, !arrangementIsManual {
                let cluster = RuntimeLayoutCoordinator.sameAppCluster(of: strand, in: liveItems)
                let crossingSide: RuntimePositionStore.BoundarySide = switch destination {
                case .rightOfItem: .rightOfDivider
                case .leftOfItem: .leftOfDivider
                @unknown default: .rightOfDivider
                }
                let trace = tracePositionWrite(
                    context: "boundary repair cluster crossing \(destination.logString)",
                    items: liveItems,
                    desiredOrder: cluster.map(\.uniqueIdentifier)
                )
                let crossed = RuntimePositionStore.writeClusterBoundaryCrossing(
                    items: cluster,
                    dividerItem: destination.targetItem,
                    side: crossingSide,
                    liveItems: liveItems
                )
                trace?.finish(result: "crossed=\(crossed)")
                if crossed {
                    let verify = await verifyBoundaryRepairAfterWrite(
                        strand: strand,
                        controller: controller,
                        controlItems: controlItems,
                        experimentalSystemItemHiding: experimentalSystemItemHiding,
                        via: "cluster crossing write"
                    )
                    liveItems = verify.items
                    if verify.verdict == .aborted {
                        return (verify.items, true, false)
                    }
                    if verify.verdict == .repaired {
                        continue
                    }
                }
            }

            // Rung 2.75, second pass only: once bar and weights diverge, single
            // drags get re-sorted back, so respace the whole visible ladder.
            let strandTripsID = MenuBarItemManager.PostRestrictionRepairItemID(
                uniqueIdentifier: strand.uniqueIdentifier,
                ownerPID: strand.ownerPID
            )
            if (boundaryRepairStrandTrips[strandTripsID] ?? 0) >= 1 {
                let authored = controller.sectionItemOrder[.visible] ?? []
                if authored.count > 1 {
                    let trace = tracePositionWrite(
                        context: "boundary repair visible respace for \(strand.uniqueIdentifier)",
                        items: liveItems,
                        desiredOrder: authored
                    )
                    let changed = MenuBarPositionStoreProvider.current.respaceOrder(
                        desiredOrder: authored,
                        liveItems: liveItems,
                        experimentalSystemItemHiding: experimentalSystemItemHiding,
                        // The boundary repair answers a reveal the user asked
                        // for; see the interleaved-unplaceable note in the
                        // structural normalization above.
                        mayRewriteAroundUnplaceableItems: true
                    )
                    trace?.finish(result: String(describing: changed))
                    if !changed.isEmpty {
                        commitPreferredPositionWrite(controller: controller)
                        liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                        guard !arrangementIsManual, !Task.isCancelled else { return (liveItems, true, false) }
                        MenuBarItemManager.diagLog.info(
                            "boundary repair: rewrote the visible ladder (\(changed.count) weight(s)) for \(strand.logString)"
                        )
                    }
                }
            }

            // Rung 3, the normal move pipeline without drags. A nonthrowing
            // return can be false, so verify the strand itself. Concealed items wait.
            if controller.section(for: strand) != .visible {
                MenuBarItemManager.diagLog.debug(
                    "boundary repair: \(strand.logString) is currently concealed; deferring move"
                )
                break
            }
            let inputIdle = await waitForUserToPauseInput(timeout: .seconds(1.5))
            guard !arrangementIsManual, !Task.isCancelled else { return (liveItems, true, false) }
            if !inputIdle {
                MenuBarItemManager.diagLog.debug(
                    "boundary repair: user input never idled; attempting move for \(strand.logString)"
                )
            }
            // Target the cluster's leading member, then verify the original
            // strand rather than assuming that a leader move repaired it.
            let dragItem = RuntimeLayoutCoordinator.sameAppClusterLeader(of: strand, in: liveItems) ?? strand
            if dragItem.tag != strand.tag {
                MenuBarItemManager.diagLog.info(
                    "boundary repair: moving cluster leader \(dragItem.logString) for \(strand.logString)"
                )
            }
            do {
                let fulfilled = try await move(
                    item: dragItem,
                    to: destination,
                    skipInputPause: true,
                    allowSectionBoundaryTarget: true
                )
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                guard !arrangementIsManual, !Task.isCancelled else { return (liveItems, true, false) }
                if MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                    items: liveItems,
                    item: strand,
                    section: .visible,
                    controlItems: controlItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                ) {
                    MenuBarItemManager.diagLog.info(
                        "Repaired macOS 27 visible boundary for \(strand.logString) via verified move"
                    )
                    continue
                }
                // The move may decline without throwing. An unchanged frame
                // plus an unsatisfied boundary earns the same extra trip as
                // the error path; movement alone is not proof of repair.
                let after = liveItems.first { $0.windowID == dragItem.windowID }
                    ?? liveItems.first { $0.uniqueIdentifier == dragItem.uniqueIdentifier }
                if let after,
                   abs(after.bounds.minX - dragItem.bounds.minX) < MenuBarItemGeometry.phantomFrameXTolerance
                {
                    boundaryRepairStrandTrips[strandTripsID, default: 0] += 1
                }
                MenuBarItemManager.diagLog.info(
                    "boundary repair: \(strand.logString) remains stranded after move (fulfilled=\(fulfilled))"
                )
            } catch is CancellationError {
                return (liveItems, true, true)
            } catch {
                guard !arrangementIsManual, !Task.isCancelled else { return (liveItems, true, false) }
                MenuBarItemManager.diagLog.error(
                    "macOS 27 visible boundary repair failed for \(strand.logString): \(error)"
                )
                // A drag that leaves the frame where it was grabbed a trapped or
                // bounced item; more drags will not change that, so it retires.
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                guard !arrangementIsManual, !Task.isCancelled else { return (liveItems, true, false) }
                let after = liveItems.first { $0.windowID == dragItem.windowID }
                    ?? liveItems.first { $0.uniqueIdentifier == dragItem.uniqueIdentifier }
                if let after,
                   abs(after.bounds.minX - dragItem.bounds.minX) < MenuBarItemGeometry.phantomFrameXTolerance
                {
                    boundaryRepairStrandTrips[strandTripsID, default: 0] += 1
                    MenuBarItemManager.diagLog.info(
                        "boundary repair: \(strand.logString) never moved (x=\(Int(after.bounds.minX))); trapped or bounced"
                    )
                }
                break
            }
        }

        recordBoundaryRepairOutcomes(
            attempted: pass.attempted,
            liveItems: liveItems,
            controlItems: controlItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )

        return (liveItems, false, pass.needsRetry(in: failingStrands()))
    }

    /// The verdict of a repair write followed by its bar-side check. A write can
    /// report success while the bar disagrees, so the check is the truth.
    private enum BoundaryRepairVerdict: Equatable {
        case repaired
        case notRepaired
        case aborted
    }

    /// Records a repair write, waits for MenuBarAgent to re-sort, and re-checks
    /// the strand's boundary. Returns the refreshed geometry with the verdict;
    /// aborted means the pass must stop and return (items, true, false).
    private func verifyBoundaryRepairAfterWrite(
        strand: MenuBarItem,
        controller: any MenuBarSectionControlling,
        controlItems: ControlItemPair,
        experimentalSystemItemHiding: Bool,
        via label: String
    ) async -> (items: [MenuBarItem], verdict: BoundaryRepairVerdict) {
        commitPreferredPositionWrite(controller: controller)
        let refreshed = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard !arrangementIsManual, !Task.isCancelled else {
            return (refreshed, .aborted)
        }
        if MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
            items: refreshed,
            item: strand,
            section: .visible,
            controlItems: controlItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) {
            MenuBarItemManager.diagLog.info(
                "Repaired macOS 27 visible boundary for \(strand.logString) via \(label)"
            )
            return (refreshed, .repaired)
        }
        return (refreshed, .notRepaired)
    }

    /// A repaired item's history is cleared; one still stranded after
    /// boundaryRepairTripLimit consecutive passes is not retried this session.
    private func recordBoundaryRepairOutcomes(
        attempted: [MenuBarItem],
        liveItems: [MenuBarItem],
        controlItems: ControlItemPair,
        experimentalSystemItemHiding: Bool
    ) {
        guard !arrangementIsManual, !Task.isCancelled else { return }
        var scored = Set<PostRestrictionRepairItemID>()
        for strand in attempted {
            let id = postRestrictionRepairItemID(for: strand)
            guard scored.insert(id).inserted else { continue }

            if MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesSectionBoundary(
                items: liveItems,
                item: strand,
                section: .visible,
                controlItems: controlItems,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) {
                boundaryRepairStrandTrips[id] = nil
                continue
            }

            let trips = (boundaryRepairStrandTrips[id] ?? 0) + 1
            guard trips >= MenuBarItemManager.boundaryRepairTripLimit else {
                boundaryRepairStrandTrips[id] = trips
                continue
            }

            boundaryRepairStrandTrips[id] = nil
            suppressedBoundaryRepairItemIDs.insert(id)
            suppressedBoundaryRepairAt[id] = Date()
            seededStrandedRepairItemIDs.insert(id)
            failureLedger.recordStrand(for: strand)
            MenuBarItemManager.diagLog.error(
                "post-restriction repair: suppressing boundary repair for persistently stranded " +
                    "\(strand.logString) after \(trips) passes " +
                    "\(boundaryRepairStrandDiagnostics(for: strand, liveItems: liveItems, controlItems: controlItems)) " +
                    ", check RuntimePositionStore.applyOrder re-seat"
            )
        }
    }

    /// Logged once on trip. A visible-side weight still seated hidden points
    /// at the axis inference, not the write.
    private func boundaryRepairStrandDiagnostics(
        for strand: MenuBarItem,
        liveItems: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> String {
        let frame = "frame=\(Int(strand.bounds.minX)),\(Int(strand.bounds.minY))" +
            " \(Int(strand.bounds.width))x\(Int(strand.bounds.height))"

        let positions = MenuBarPositionStoreProvider.current.currentPositions()
        guard !positions.isEmpty else {
            return "\(frame) weights=unavailable"
        }
        let keys = Array(positions.keys)

        func weight(of item: MenuBarItem) -> Int? {
            MenuBarPositionStoreProvider.current.resolveKey(
                for: item,
                existingKeys: keys,
                positions: positions,
                liveItems: liveItems
            ).flatMap { positions[$0] }
        }

        let strandWeight = weight(of: strand).map(String.init) ?? "none"
        let dividerWeight = weight(of: controlItems.hidden).map(String.init) ?? "none"
        return "\(frame) weight=\(strandWeight) hiddenDividerWeight=\(dividerWeight)"
    }

    /// Reads live weights, not the desired order, which can be gathered while
    /// the weights the agent sorts by are still interleaved.
    private func isAnyGroupInterleaved(in desiredOrder: [String]) -> Bool {
        guard let appState else { return false }
        let items = MenuBarSection.Name.allCases.flatMap { appState.itemManager.managedItems(for: $0) }
        let groups = Self.groupPolicySet(for: items, appState: appState)
        guard !groups.isEmpty else { return false }

        let positions = MenuBarPositionStoreProvider.current.currentPositions()
        guard !positions.isEmpty else { return false }
        let keys = Array(positions.keys)

        var weightByIdentifier = [String: Int]()
        for item in items {
            guard let key = MenuBarPositionStoreProvider.current.resolveKey(
                for: item,
                existingKeys: keys,
                positions: positions,
                liveItems: items
            ), let weight = positions[key] else {
                continue
            }
            weightByIdentifier[item.uniqueIdentifier] = weight
        }

        // Only groups that actually live in the order being applied. A group
        // sitting entirely in Hidden is not this pass's problem, and re-spacing
        // the visible segment would not help it anyway.
        let inScope = Set(desiredOrder)
        for group in groups.groups where group.contains(where: inScope.contains) {
            let memberWeights = group.compactMap { weightByIdentifier[$0] }
            guard memberWeights.count >= 2,
                  let low = memberWeights.min(),
                  let high = memberWeights.max()
            else {
                continue
            }
            let memberSet = Set(group)
            let interloper = weightByIdentifier.contains { identifier, weight in
                !memberSet.contains(identifier) && weight > low && weight < high
            }
            if interloper {
                return true
            }
        }
        return false
    }

    /// - Parameter visibleOrderOverride: Replaces the authored Visible order
    ///   for this pass: reveals pass the mirrored bar order, and pane edits the
    ///   freshly committed order.
    /// - Parameter reason: Decides enforcement and every exemption, so a caller
    ///   cannot grant itself privileges.
    func applySectionItemOrder(
        sections: [MenuBarSection.Name],
        controller: any MenuBarSectionControlling,
        whileRevealing revealedSection: MenuBarSection.Name? = nil,
        repairAfterRestriction: Bool = false,
        visibleOrderOverride: [String]? = nil,
        reason: LayoutChangeReason,
        preferredMoveUIDs: Set<String> = []
    ) async {
        // The skip gates are pure policy, in SectionOrderApplyGate; a pass
        // an earlier gate refuses never pays for the lazier reads.
        if skipSectionOrderApply(
            controller: controller,
            revealedSection: revealedSection,
            repairAfterRestriction: repairAfterRestriction,
            reason: reason
        ) {
            return
        }
        let isUserInitiated = reason.isUserInitiated

        // Drags warp the cursor, so wait briefly for the hand to go idle.
        // Once per pass and bounded, so a pending edit cannot stall.
        if menuBarAgentIgnoresPreferredPositions {
            let paused = await waitForUserToPauseInput(timeout: .seconds(1.5))
            if !paused {
                MenuBarItemManager.diagLog.info(
                    "macOS 27 section order: user input never idled within the pause bound; proceeding"
                )
            }
        }

        // Tracks whether any item actually moved this pass, so the layout UI's
        // screen capture is refreshed only when the bar changed, not on every
        // idle reconcile (each macOS 27 capture is a heavy full screenshot).
        var didReorder = false
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding

        for section in sections {
            guard !Task.isCancelled,
                  revealedSection == nil || controller.revealedSection == revealedSection
            else { return }
            let recordedOrder = if section == .visible, let visibleOrderOverride {
                visibleOrderOverride
            } else {
                controller.sectionItemOrder[section] ?? []
            }
            var desiredOrder = recordedOrder
                .filter { controller.section(for: $0) == section }
            guard desiredOrder.count > 1 else {
                continue
            }

            var liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            // A newcomer from a hidden section can take seconds to republish,
            // and one missing from the snapshot keeps its far-side weight.
            // Wait, bounded, until every visible member is live.
            if section == .visible {
                let republished = await awaitVisibleMembersRepublished(desiredOrder: desiredOrder)
                liveItems = republished.liveItems
                desiredOrder = republished.desiredOrder
            }

            // AX enumeration can finish after a hide cancelled this reveal.
            // Revalidate before the first write, not only in the per-pair loop:
            // a cancelled batch otherwise changes the next reveal's order.
            guard !Task.isCancelled,
                  revealedSection == nil || controller.revealedSection == revealedSection
            else { return }

            // One cursor-free write for the whole section first; the per-pair
            // loop fixes any residue after the agent re-sorts.
            if !menuBarAgentIgnoresPreferredPositions {
                let write = await applyCursorFreeSectionWrite(
                    section: section,
                    desiredOrder: desiredOrder,
                    liveItems: liveItems,
                    experimentalSystemItemHiding: experimentalSystemItemHiding,
                    reason: reason,
                    controller: controller
                )
                liveItems = write.liveItems
                didReorder = didReorder || write.didReorder
            }

            // After a restriction reflow drags fail and strand collateral; the
            // write above is enough. A write-only reason never drags at all.
            if repairAfterRestriction || reason.isPositionWriteOnly {
                continue
            }

            /// Items hidden by macOS are still enumerated, but cannot be
            /// dragged. Keep them out of both plans and postcondition checks.
            func plannableItems(in items: [MenuBarItem]) -> [MenuBarItem] {
                let sectionItems = items.filter {
                    MenuBarLayoutPlannerProvider.current.isEligibleForSectionOrder($0, section: section) &&
                        controller.section(for: $0) == section
                }
                for item in sectionItems where Self.isHiddenBySystemPreferences(item) {
                    if Self.loggedSystemHiddenItems.insert(item.uniqueIdentifier).inserted {
                        MenuBarItemManager.diagLog.notice(
                            "excluding \(item.logString): hidden by macOS (System Settings per-item toggle)"
                        )
                    }
                }
                return sectionItems.filter { !Self.isHiddenBySystemPreferences($0) }
            }

            // Confirm each move before it can anchor another; one replan is
            // allowed after an invalidation. Pairwise mode stops at a blocked
            // pair because it would pick it again.
            let usesPlan = Self.usesLCSSectionOrderPlanner
            var plannedQueue: LayoutMoveSequenceExecution?
            var replanCount = 0
            let maximumReplans = 1
            let maximumMoves = max(1, desiredOrder.count * 2)
            for _ in 0 ..< maximumMoves {
                guard !Task.isCancelled else { return }
                if let revealedSection, controller.revealedSection != revealedSection {
                    return
                }

                // Yield to a waiting user reorder rather than issue more
                // background pairs. A user pass never yields to itself.
                if !isUserInitiated, pendingUserReorderCount > 0 {
                    MenuBarItemManager.diagLog.info(
                        "macOS 27 section order: yielding to \(pendingUserReorderCount) pending user reorder(s)"
                    )
                    return
                }

                let plannable = plannableItems(in: liveItems)
                let plannedMove: (item: MenuBarItem, destination: MoveDestination, isBoundary: Bool)
                if usesPlan {
                    if plannedQueue == nil {
                        let queue = Self.planSectionMoves(
                            items: plannable,
                            desiredOrder: desiredOrder,
                            section: section,
                            experimentalSystemItemHiding: experimentalSystemItemHiding,
                            preferredMoveUIDs: preferredMoveUIDs
                        )
                        MenuBarItemManager.diagLog.info(
                            "macOS 27 section order: planned \(queue.count) move(s) for \(section.logString)"
                        )
                        plannedQueue = LayoutMoveSequenceExecution(moves: queue)
                    }
                    guard var queue = plannedQueue else { break }
                    let resolved = Self.nextResolvedPlannedMove(
                        from: &queue,
                        in: liveItems,
                        controlItems: controlItemPair(in: liveItems)
                    )
                    plannedQueue = queue
                    guard let next = resolved else {
                        if queue.needsReplan {
                            guard replanCount < maximumReplans else {
                                MenuBarItemManager.diagLog.info(
                                    "macOS 27 section order: invalidated plan stopped in \(section.logString); replan budget exhausted"
                                )
                                break
                            }
                            replanCount += 1
                            // A failed drag may have partially displaced the
                            // bar. Settle and re-read before making a new plan.
                            do {
                                try await Task.sleep(for: .milliseconds(120))
                            } catch {
                                return
                            }
                            liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                            plannedQueue = nil
                            MenuBarItemManager.diagLog.info(
                                "macOS 27 section order: replanning invalidated sequence in \(section.logString) (\(replanCount)/\(maximumReplans))"
                            )
                            continue
                        }
                        break
                    }
                    plannedMove = next
                } else {
                    guard let next = MenuBarLayoutPlannerProvider.current.nextAchievableOrderMove(
                        items: plannable,
                        desiredOrder: desiredOrder,
                        experimentalSystemItemHiding: experimentalSystemItemHiding
                    ) else {
                        break
                    }
                    plannedMove = (next.item, next.destination, false)
                }

                if let skip = sectionDragSkipReason(
                    plannedMove: plannedMove,
                    isUserInitiated: isUserInitiated,
                    usesPlan: usesPlan,
                    repairAfterRestriction: repairAfterRestriction,
                    liveItems: liveItems,
                    desiredOrder: desiredOrder
                ) {
                    if skip.endsMoveLoop {
                        break
                    }
                    continue
                }
                let itemFailureKey = Self.itemMoveFailureKey(
                    item: plannedMove.item,
                    destination: plannedMove.destination
                )
                let failureKey = Self.moveFailureKey(
                    item: plannedMove.item,
                    destination: plannedMove.destination,
                    desiredOrder: desiredOrder
                )

                do {
                    let fulfilled = try await move(
                        item: plannedMove.item,
                        to: plannedMove.destination,
                        skipInputPause: true,
                        allowSectionBoundaryTarget: plannedMove.isBoundary,
                        allowParkedOffMenuBarSource: repairAfterRestriction
                    )
                    guard fulfilled else {
                        recentMoveFailures[failureKey] = .now
                        recordItemMoveFailure(key: itemFailureKey)
                        MenuBarItemManager.diagLog.debug(
                            "Could not fulfill macOS 27 section order move via preferred positions: " +
                                "\(plannedMove.item.logString) → \(plannedMove.destination.logString)"
                        )
                        if usesPlan {
                            plannedQueue?.invalidate()
                            continue
                        }
                        break
                    }
                    plannedQueue?.confirmLastMove()
                    recentMoveFailures.removeValue(forKey: failureKey)
                    clearItemMoveFailure(key: itemFailureKey)
                    didReorder = true
                    MenuBarItemManager.diagLog.info(
                        "Applied macOS 27 achievable order in \(section.logString) for \(plannedMove.item.logString)"
                    )
                } catch {
                    recentMoveFailures[failureKey] = .now
                    recordItemMoveFailure(key: itemFailureKey)
                    MenuBarItemManager.diagLog.error(
                        "Failed to apply macOS 27 section order for \(plannedMove.item.logString): \(error)"
                    )
                    if usesPlan {
                        plannedQueue?.invalidate()
                        continue
                    }
                    break
                }

                // Resolve the next move against settled geometry. Failed drags
                // instead invalidate the queue and refresh in the replan path.
                try? await Task.sleep(for: .milliseconds(120))
                liveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }

            // Check residue without dragging it. An incomplete plan never
            // reaches this success-path check.
            if usesPlan, let plannedQueue, plannedQueue.isComplete,
               let residue = MenuBarLayoutPlannerProvider.current.nextAchievableOrderMove(
                   items: plannableItems(in: liveItems),
                   desiredOrder: desiredOrder,
                   experimentalSystemItemHiding: experimentalSystemItemHiding
               )
            {
                MenuBarItemManager.diagLog.info(
                    "macOS 27 section order: LCS pass left residue in \(section.logString): " +
                        "\(residue.item.logString) \(residue.destination.logString)"
                )
            }
        }

        // The capture key ignores position and the live loop skips ticks near a
        // move, so poke it or the layout UI keeps the pre-reorder screenshot.
        if didReorder {
            await appState?.imageCache.refreshAfterReorder()
        }
    }

    /// The skip gates for one section-order pass, in order; the screen and
    /// budget checks are read lazily. Returns whether the pass must stop.
    private func skipSectionOrderApply(
        controller: any MenuBarSectionControlling,
        revealedSection: MenuBarSection.Name?,
        repairAfterRestriction: Bool,
        reason: LayoutChangeReason
    ) -> Bool {
        // Also checked here: the opening whole-section write bypasses move(item:to:),
        // and refused moves would otherwise earn a failure backoff for a lock.
        if refuseMenuBarMutationWhileScreenLocked("section order apply") {
            return true
        }
        guard let rejection = SectionOrderApplyGate.firstRejection(.init(
            isCancelled: Task.isCancelled,
            controllerRevealedSection: controller.revealedSection,
            revealedSection: revealedSection,
            circuitBreakerOpen: moveCircuitBreaker.isOpen,
            reason: reason,
            arrangementIsManual: arrangementIsManual,
            isExplicitLayoutEdit: ExplicitLayoutEdit.isActive,
            nativeMenuBarDeferred: appState?.menuBarManager.shouldDeferBarMutation == true,
            isWithinSettleWindow: isWithinRestrictionReflowSettleWindow,
            repairAfterRestriction: repairAfterRestriction,
            applicationMenuWrapsPastNotch: {
                guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main,
                      MenuBarCapacitySnapshot.applicationMenuWrapsPastNotch(on: screen)
                else { return nil }
                return String(screen.displayID)
            },
            isConvergenceBudgetExhausted: { [weak self] in self?.isConvergenceBudgetExhausted() ?? false },
            prefersPositionWrites: menuBarAgentIgnoresPreferredPositions
        )) else { return false }
        switch rejection {
        case .cancelled, .revealMismatch:
            break
        case .circuitBreakerOpen:
            MenuBarItemManager.diagLog.debug(
                "Move circuit breaker open; skipping automatic section order apply"
            )
        case .reasonAcceptsSettledOrder:
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: \(String(describing: reason)) accepts the settled order"
            )
        case .manualArrangement:
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: manual arrangement, and this pass is not a Layout edit"
            )
        case .nativeMenuBarUnavailable:
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: native menu bar unavailable/transitioning"
            )
        case .restrictionReflowSettleWindow:
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: within restriction-reflow settle window"
            )
        case let .applicationMenuWrapsPastNotch(displayID):
            MenuBarItemManager.diagLog.info(
                "Skipping macOS 27 section order: application menu wraps past the notch on display \(displayID)"
            )
        case .convergenceBudgetExhausted:
            MenuBarItemManager.diagLog.debug(
                "Skipping macOS 27 section order: convergence budget exhausted"
            )
        }
        return true
    }

    /// Waits, bounded, for visible members that can still arrive. Pinned items
    /// never arrive late, so they are not waited on; absentees are dropped.
    private func awaitVisibleMembersRepublished(
        desiredOrder: [String]
    ) async -> (liveItems: [MenuBarItem], desiredOrder: [String]) {
        let wantedIDs = Set(desiredOrder)
        let now = ContinuousClock.now
        visibleMembersMissingRepublish = visibleMembersMissingRepublish.filter {
            $0.value.duration(to: now) < Self.missingRepublishMemory
        }
        // Wait only for members that can still arrive; an empty wait
        // set is satisfied by the first enumeration.
        let knownAbsent = wantedIDs.filter {
            visibleMembersMissingRepublish[$0] != nil || Self.namesPinnedSystemItem($0)
        }
        let awaitedIDs = wantedIDs.subtracting(knownAbsent)
        if !knownAbsent.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "authored visible apply: not re-waiting for \(knownAbsent.sorted().joined(separator: ", "))"
            )
        }
        let presenceWait = await waitForMenuBarAgentLayout(
            deadline: now + .seconds(3),
            interval: .milliseconds(150),
            isSatisfied: { items in
                awaitedIDs.isSubset(of: Set(items.map(\.uniqueIdentifier)))
            }
        )
        let refreshed = presenceWait.items
        let liveIDs = Set(refreshed.map(\.uniqueIdentifier))
        for identifier in wantedIDs.intersection(liveIDs) {
            visibleMembersMissingRepublish.removeValue(forKey: identifier)
        }
        var updatedOrder = desiredOrder
        let missing = wantedIDs.subtracting(liveIDs)
        if !missing.isEmpty {
            let stamp = ContinuousClock.now
            for identifier in missing {
                visibleMembersMissingRepublish[identifier] = stamp
            }
            // Named, not counted: a count cannot say which app lagged.
            MenuBarItemManager.diagLog.warning(
                "authored visible apply: \(missing.count) member(s) never republished; " +
                    "placing the rest without \(missing.sorted().joined(separator: ", "))"
            )
            updatedOrder.removeAll { missing.contains($0) }
        }
        return (refreshed, updatedOrder)
    }

    /// One cursor-free write for the section: structural for visible, a
    /// permutation otherwise. Returns refreshed geometry and whether it wrote.
    private func applyCursorFreeSectionWrite(
        section: MenuBarSection.Name,
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        reason: LayoutChangeReason,
        controller: any MenuBarSectionControlling
    ) async -> (liveItems: [MenuBarItem], didReorder: Bool) {
        // An arrival carries a far-side weight no permutation can fix, so the
        // structural write places members by authored position.
        var liveItems = liveItems
        var didReorder = false
        var structuralApplied = false
        if section == .visible {
            if let controlItems = controlItemPair(in: liveItems) {
                structuralApplied = restoreStructuralControlOrder(
                    controlItems: controlItems,
                    items: liveItems,
                    diagnosticContext: "section apply \(section.logString) reason=\(reason)"
                )
            }
        }
        if structuralApplied {
            controller.notePreferredPositionsSelfWrite()
            let nudgeRan = requestMenuBarAgentPositionRefresh()
            didReorder = true
            liveItems = await waitForMenuBarAgentResort(
                desiredOrder: desiredOrder,
                section: section,
                controller: controller,
                nudgeRan: nudgeRan
            )
        } else {
            let trace = tracePositionWrite(
                context: "section apply \(section.logString) reason=\(reason)",
                items: liveItems,
                desiredOrder: desiredOrder
            )
            let reordered = MenuBarPositionStoreProvider.forLayoutEdit.applyOrder(
                desiredOrder: desiredOrder,
                liveItems: liveItems,
                experimentalSystemItemHiding: experimentalSystemItemHiding,
                // The order pass only reaches here under a reason the
                // policy permits; see the interleaved-unplaceable note
                // in the structural normalization above.
                mayRewriteAroundUnplaceableItems: reason.permitsOrderEnforcement
            )
            trace?.finish(result: String(describing: reordered))
            if !reordered.isEmpty {
                controller.notePreferredPositionsSelfWrite()
                let nudgeRan = requestMenuBarAgentPositionRefresh()
                didReorder = true
                liveItems = await waitForMenuBarAgentResort(
                    desiredOrder: desiredOrder,
                    section: section,
                    controller: controller,
                    nudgeRan: nudgeRan
                )
            }
        }
        return (liveItems, didReorder)
    }

    /// Why a planned section-order drag is skipped, and whether the skip ends
    /// the whole move loop rather than just this move.
    private struct SectionDragSkip {
        enum Reason {
            case parked
            case circuitBreaker
            case hidingUnsupported
            case agentOwned
            case recentlyFailed
        }

        let reason: Reason
        let endsMoveLoop: Bool
    }

    /// The drag-skip checks for one planned section-order move, in order. Side
    /// effects, including the failure-key writes, stay here so every skip is
    /// recorded exactly once.
    private func sectionDragSkipReason(
        plannedMove: (item: MenuBarItem, destination: MoveDestination, isBoundary: Bool),
        isUserInitiated: Bool,
        usesPlan: Bool,
        repairAfterRestriction: Bool,
        liveItems: [MenuBarItem],
        desiredOrder: [String]
    ) -> SectionDragSkip? {
        if !repairAfterRestriction,
           plannedMove.item.isParkedOffMenuBarBand(among: liveItems)
        {
            MenuBarItemManager.diagLog.debug(
                "Deferring macOS 27 section order for parked \(plannedMove.item.logString)"
            )
            return SectionDragSkip(reason: .parked, endsMoveLoop: true)
        }

        // Item-scoped breaker, keyed on item, side and target, since an
        // overflowing bar changes the order-keyed backoff's key every pass.
        // User passes are exempt.
        let itemFailureKey = Self.itemMoveFailureKey(
            item: plannedMove.item,
            destination: plannedMove.destination
        )
        if !isUserInitiated, isItemMoveCircuitBreakerTripped(key: itemFailureKey) {
            MenuBarItemManager.diagLog.info(
                "Circuit breaker: suppressing automatic macOS 27 drag for " +
                    "\(plannedMove.item.logString) \(plannedMove.destination.logString) " +
                    "(\(recentItemMoveFailures[itemFailureKey]?.count ?? 0) recent verify-failures)"
            )
            return SectionDragSkip(reason: .circuitBreaker, endsMoveLoop: !usesPlan)
        }

        // Hiding-unsupported items rewrite their AX title too often to drag;
        // only the store can move them, so back off.
        if plannedMove.item.tag.isHidingUnsupported ||
            plannedMove.destination.targetItem.tag.isHidingUnsupported
        {
            let failureKey = Self.moveFailureKey(
                item: plannedMove.item,
                destination: plannedMove.destination,
                desiredOrder: desiredOrder
            )
            recentMoveFailures[failureKey] = .now
            MenuBarItemManager.diagLog.debug(
                "Skipping synthetic drag for denylisted hiding-unsupported item in macOS 27 section order: " +
                    "\(plannedMove.item.logString) → \(plannedMove.destination.logString)"
            )
            return SectionDragSkip(reason: .hidingUnsupported, endsMoveLoop: !usesPlan)
        }

        // Agent-composited extras (such as the Live Activity pill) ignore
        // Command-drags, so skip before the cursor warps.
        if plannedMove.item.tag.namespace == .menuBarAgent {
            MenuBarItemManager.diagLog.debug(
                "Skipping synthetic drag for agent-owned item in macOS 27 section order: \(plannedMove.item.logString)"
            )
            return SectionDragSkip(reason: .agentOwned, endsMoveLoop: !usesPlan)
        }

        // Some system extras (such as Sound) always reject the drag; without
        // backoff it replans every cycle in a cursor-warp loop. Repair passes
        // included: two failures already covered the retry.
        let failureKey = Self.moveFailureKey(
            item: plannedMove.item,
            destination: plannedMove.destination,
            desiredOrder: desiredOrder
        )
        if let lastFailure = recentMoveFailures[failureKey],
           ContinuousClock.now - lastFailure < Self.moveFailureBackoff
        {
            MenuBarItemManager.diagLog.debug(
                "Skipping recently-failed macOS 27 section order move for \(plannedMove.item.logString) \(plannedMove.destination.logString)"
            )
            return SectionDragSkip(reason: .recentlyFailed, endsMoveLoop: !usesPlan)
        }
        return nil
    }

    /// The outcome of one waitForMenuBarAgentLayout(deadline:interval:enumerate:isSatisfied:)
    /// poll loop.
    struct MenuBarAgentLayoutWaitResult {
        /// The most recent enumeration.
        let items: [MenuBarItem]
        /// Whether any item's origin shifted while polling. false means
        /// MenuBarAgent never acted on the write at all.
        let barMoved: Bool
        /// A cancelled wait proves nothing about the agent, so it is not a refusal.
        let cancelled: Bool
        let observationUnavailable: Bool
    }

    /// Waits for the agent to re-sort after a write, until isSatisfied or the
    /// deadline. A wall-clock deadline, since each poll costs an AX walk, and
    /// waits in one move can share it. barMoved says whether the bar reacted.
    private func waitForMenuBarAgentLayout(
        deadline: ContinuousClock.Instant? = nil,
        interval: Duration = Constants.MenuBarTuning.menuBarAgentResortPollInterval,
        earlyBailProbe: Duration? = nil,
        enumerate: () async -> [MenuBarItem]? = { await MenuBarItem.getMenuBarItems(option: .activeSpace, freshOnly: true) },
        isSatisfied: ([MenuBarItem]) -> Bool
    ) async -> MenuBarAgentLayoutWaitResult {
        guard var liveItems = await enumerate() else {
            return MenuBarAgentLayoutWaitResult(
                items: [], barMoved: false, cancelled: Task.isCancelled, observationUnavailable: true
            )
        }
        let deadline = deadline ?? Self.menuBarAgentResortDeadline(
            timeout: configuration.menuBarOrderFulfillmentTimeout
        )
        let originalGeometry = Self.layoutGeometrySignature(liveItems)
        var barMoved = false
        // If nothing moved by earlyBailProbe the agent dropped the write.
        // Once anything moves, barMoved latches and the wait runs its course.
        let earlyBailDeadline = earlyBailProbe.map { ContinuousClock.now + $0 }

        // Check the existing walk first, so an instantly honored write costs
        // no sleep and no second walk.
        if isSatisfied(liveItems) {
            return MenuBarAgentLayoutWaitResult(
                items: liveItems, barMoved: false, cancelled: false, observationUnavailable: false
            )
        }

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: interval)
            } catch {
                // try? here would spin AX walks and escalate a healthy write
                // to a drag.
                return MenuBarAgentLayoutWaitResult(
                    items: liveItems,
                    barMoved: barMoved,
                    cancelled: true,
                    observationUnavailable: false
                )
            }
            guard let observedItems = await enumerate() else {
                return MenuBarAgentLayoutWaitResult(
                    items: [], barMoved: barMoved, cancelled: Task.isCancelled, observationUnavailable: true
                )
            }
            liveItems = observedItems
            if !barMoved, Self.layoutGeometryChanged(
                from: originalGeometry,
                to: Self.layoutGeometrySignature(liveItems)
            ) {
                barMoved = true
            }
            if isSatisfied(liveItems) {
                break
            }
            // Nothing has shifted by the probe window: the agent dropped the
            // write. Stop here rather than watching a frozen bar for the rest
            // of the deadline.
            if !barMoved, let earlyBailDeadline, ContinuousClock.now >= earlyBailDeadline {
                break
            }
        }
        return MenuBarAgentLayoutWaitResult(
            items: liveItems, barMoved: barMoved, cancelled: false, observationUnavailable: false
        )
    }

    /// Converts the user-facing fulfillment window into a wall-clock deadline,
    /// clamping malformed persisted values to the Layout control's range.
    static nonisolated func menuBarAgentResortDeadline(
        timeout: TimeInterval,
        from start: ContinuousClock.Instant = ContinuousClock.now
    ) -> ContinuousClock.Instant {
        start + .seconds(clampedResortTimeout(timeout))
    }

    /// Clamps a persisted fulfillment timeout to the Layout control's range.
    static nonisolated func clampedResortTimeout(_ timeout: TimeInterval) -> TimeInterval {
        min(max(timeout, 1), 15)
    }

    /// A cheap fingerprint of where every item currently sits. Comparing two of
    /// these tells a preferred-position write MenuBarAgent ignored (every origin
    /// identical) from one it is still working through.
    static nonisolated func layoutGeometrySignature(_ items: [MenuBarItem]) -> [String: CGFloat] {
        items.reduce(into: [:]) { signature, item in
            signature[item.uniqueIdentifier] = item.bounds.minX
        }
    }

    /// Only an item present in both snapshots that moved at least epsilon
    /// counts, so rows blinking in and out never read as motion.
    static nonisolated func layoutGeometryChanged(
        from original: [String: CGFloat],
        to current: [String: CGFloat],
        epsilon: CGFloat = 1
    ) -> Bool {
        for (identifier, x) in current {
            guard let previous = original[identifier] else { continue }
            if abs(x - previous) >= epsilon {
                return true
            }
        }
        return false
    }

    /// Waits for the re-sort after a batch applyOrder write, until section
    /// satisfies desiredOrder or a short budget elapses.
    private func waitForMenuBarAgentResort(
        desiredOrder: [String],
        section: MenuBarSection.Name,
        controller: any MenuBarSectionControlling,
        nudgeRan: Bool
    ) async -> [MenuBarItem] {
        let experimentalSystemItemHiding = configuration.enableExperimentalSystemItemHiding
        let orderSatisfied: ([MenuBarItem]) -> Bool = { items in
            let sectionItems = items.filter {
                MenuBarLayoutPlannerProvider.current.isEligibleForSectionOrder($0, section: section) &&
                    controller.section(for: $0) == section
            }
            return MenuBarLayoutPlannerProvider.current.nextAchievableOrderMove(
                items: sectionItems,
                desiredOrder: desiredOrder,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) == nil
        }
        let waitResult = await waitForMenuBarAgentLayout(isSatisfied: orderSatisfied)
        let liveItems = waitResult.items
        if orderSatisfied(liveItems) {
            MenuBarItemManager.diagLog.info(
                "Batch preferred-position order satisfied for \(section.logString)"
            )
        } else if !waitResult.barMoved, !waitResult.cancelled {
            // The agent dropped the write. Only evidence if the nudge ran.
            if nudgeRan {
                MenuBarItemManager.diagLog.warning(
                    "Batch preferred-position write ignored by MenuBarAgent for \(section.logString)"
                )
                noteMenuBarAgentIgnoredPreferredPositions()
            } else {
                MenuBarItemManager.diagLog.debug(
                    "Batch preferred-position write unverified (nudge skipped) for \(section.logString)"
                )
            }
        }
        return liveItems
    }

    /// The live walk plus every cached managed item it does not carry, matched
    /// by tag regardless of window ID. Live geometry wins where both exist;
    /// a cached member only fills a gap the assertion has not re-allowed yet.
    static nonisolated func completingPartialWalk(
        _ liveItems: [MenuBarItem],
        with cachedItems: [MenuBarItem]
    ) -> [MenuBarItem] {
        let missing = cachedItems.filter { cached in
            !liveItems.contains { $0.tag.matchesIgnoringWindowID(cached.tag) }
        }
        guard !missing.isEmpty else { return liveItems }
        // Insert at the last-known frame, not appended, or a concealed item's
        // slot lands in the visible lane. Never-rendered items go last.
        return (liveItems + missing).enumerated()
            .sorted { lhs, rhs in
                let lhsMissing = lhs.element.bounds.isEmpty && !liveItems.contains { $0.tag.matchesIgnoringWindowID(lhs.element.tag) }
                let rhsMissing = rhs.element.bounds.isEmpty && !liveItems.contains { $0.tag.matchesIgnoringWindowID(rhs.element.tag) }
                switch (lhsMissing, rhsMissing) {
                case (true, false): return false
                case (false, true): return true
                default:
                    if lhs.element.bounds.minX != rhs.element.bounds.minX {
                        return lhs.element.bounds.minX < rhs.element.bounds.minX
                    }
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// authored with item moved beside the target, so a respace realizes the
    /// move. Unchanged when the target is not in the record; a new arrival is
    /// inserted. Control items are never applied: laddering one can invert
    /// the dividers, and their seats are the structural pass's call.
    static nonisolated func authoredOrder(
        _ authored: [String],
        applying destination: MoveDestination,
        to item: MenuBarItem
    ) -> [String] {
        guard !item.isControlItem, !destination.targetItem.isControlItem else { return authored }
        let itemID = item.uniqueIdentifier
        let targetID = destination.targetItem.uniqueIdentifier
        guard targetID != itemID, authored.contains(targetID) else { return authored }
        var order = authored.filter { $0 != itemID }
        guard let targetIndex = order.firstIndex(of: targetID) else { return authored }
        order.insert(itemID, at: destination.isRightward ? targetIndex + 1 : targetIndex)
        return order
    }

    /// The divider side a boundary-crossing write targets for destination.
    private func crossingSide(of destination: MoveDestination) -> RuntimePositionStore.BoundarySide {
        switch destination {
        case .leftOfItem: return .leftOfDivider
        case .rightOfItem: return .rightOfDivider
        @unknown default: return .rightOfDivider
        }
    }

    /// The cursor-free move: rewrite the agent's preferred-position weight.
    /// True only when the live order then satisfies destination, since the
    /// key spelling is uncertain; false falls back to the Command-drag.
    private func moveItemViaPreferredPositions(
        item: MenuBarItem,
        to destination: MoveDestination,
        transitionSection: MenuBarSection.Name? = nil,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        isUserInitiated: Bool = false
    ) async throws -> Bool {
        guard !menuBarAgentIgnoresPreferredPositions else {
            moveMonitor.recordStoreUnavailable()
            return false
        }
        guard !ignoredPreferredWrites.skipsWrite(for: item.uniqueIdentifier) else {
            MenuBarItemManager.diagLog.debug(
                "MenuBarAgent ignored the last preferred-position writes for \(item.logString); dragging instead"
            )
            return false
        }

        // The user's own move is the retry that clears the breaker, so it must
        // reach the store even during a cooldown; only automatic passes wait.
        if moveCircuitBreaker.note(.storeWrite) {
            guard isUserInitiated else {
                MenuBarItemManager.diagLog.debug("Move circuit breaker open; skipping store write for \(item.logString)")
                return false
            }
            MenuBarItemManager.diagLog.debug("Move circuit breaker open; allowing the user's store write for \(item.logString)")
        }
        // Held across the write and its verification: a structural re-lay in
        // this window renumbers the slot claimed below, and the move is judged
        // to have failed on the strength of Thaw's own overwrite.
        pendingPreferredPositionMoves += 1
        defer { pendingPreferredPositionMoves -= 1 }
        try Task.checkCancellation()

        // The single-row write never crosses a divider, which would split a
        // same-app cluster. When the authored record agrees with the crossing,
        // write the cluster's crossing weights so the move lands cursor-free.
        let trace = tracePositionWrite(
            context: "preferred move \(item.uniqueIdentifier) \(destination.logString)",
            items: liveItems,
            desiredOrder: [item.uniqueIdentifier, destination.targetItem.uniqueIdentifier]
        )
        var storeMoved = false
        if let crossingSection = destination.sectionAcrossBoundary(from: item),
           let sectionController = appState?.menuBarManager.sectionController,
           sectionController.section(for: item.uniqueIdentifier) == crossingSection || transitionSection == crossingSection
        {
            // An explicit transition has not committed its assignment yet.
            // It authorizes this member, not other same-app items outside the drop.
            let cluster = if transitionSection != nil {
                [item]
            } else {
                RuntimeLayoutCoordinator.sameAppCluster(of: item, in: liveItems)
                    .filter { sectionController.section(for: $0.uniqueIdentifier) == crossingSection }
            }
            storeMoved = RuntimePositionStore.writeClusterBoundaryCrossing(
                items: cluster.isEmpty ? [item] : cluster,
                dividerItem: destination.targetItem,
                side: crossingSide(of: destination),
                liveItems: liveItems
            )
            if storeMoved {
                sectionController.notePreferredPositionsSelfWrite()
            }
        }
        // Move the item, not the section: a full-band rewrite would replay
        // stale order and relocate unrelated items. Skip if a crossing wrote.
        if !storeMoved {
            storeMoved = MenuBarPositionStoreProvider.forLayoutEdit.move(
                item: item,
                to: destination,
                liveItems: liveItems,
                experimentalSystemItemHiding: experimentalSystemItemHiding,
                // A single-item request does not authorize moving neighbours
                // around an item whose position the store cannot resolve.
                mayRewriteAroundUnplaceableItems: false
            )
        }
        trace?.finish(result: "storeMoved=\(storeMoved)")
        guard storeMoved else {
            return false
        }
        appState?.menuBarManager.sectionController.notePreferredPositionsSelfWrite()
        let nudgeRan = requestMenuBarAgentPositionRefresh()
        // Without the nudge the agent never re-reads the table, so polling is
        // pointless. The write stays for the next re-sort to agree with.
        guard nudgeRan else {
            MenuBarItemManager.diagLog.info(
                "Preferred-position write recorded but not awaited for \(item.logString): nudge suppressed; falling back"
            )
            return false
        }
        // Stamp at issue time: the bar animates as soon as the write lands, and
        // captures mid-animation cache garbled slices. Verification re-stamps.
        moveActivity.noteMoveOperation()

        // Feeds the per-item write record on exit, only for nudged writes.
        var writeVerified = false
        var observationUnavailable = false
        defer {
            if nudgeRan, !observationUnavailable {
                if writeVerified {
                    ignoredPreferredWrites.noteVerified(item.uniqueIdentifier)
                } else if !Task.isCancelled {
                    ignoredPreferredWrites.noteUnverified(item.uniqueIdentifier)
                }
            }
        }

        // Poll the live order until MenuBarAgent observes the synchronized write.
        let destinationSatisfied: ([MenuBarItem]) -> Bool = { items in
            MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesDestination(
                items: items,
                item: item,
                destination: destination,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        }
        // One budget for the whole preferred-position phase, shared by the
        // initial wait and the key-resolution retry below, so the caller can
        // fall back within the configured window.
        let deadline = Self.menuBarAgentResortDeadline(
            timeout: configuration.menuBarOrderFulfillmentTimeout
        )
        // Bail early if the bar stays frozen past the probe, so the drag
        // fallback starts sooner; an honored write moves within a poll or two.
        let firstWait = await waitForMenuBarAgentLayout(
            deadline: deadline,
            earlyBailProbe: Constants.MenuBarTuning.menuBarAgentBarMovedProbeWindow,
            enumerate: {
                await MenuBarItem.getFreshMenuBarItemsForMove(priorityPIDs: Set([
                    item.ownerPID, item.sourcePID,
                    destination.targetItem.ownerPID, destination.targetItem.sourcePID,
                ].compactMap(\.self)))
            },
            isSatisfied: destinationSatisfied
        )
        observationUnavailable = firstWait.observationUnavailable
        guard !observationUnavailable else {
            try Task.checkCancellation()
            return false
        }
        let updated = firstWait.items
        if destinationSatisfied(updated) {
            writeVerified = true
            moveActivity.noteMoveOperation()
            MenuBarItemManager.diagLog.info(
                "Preferred-position move verified for \(item.logString) \(destination.logString)"
            )
            return true
        }

        // A failed single-item write is not authority to replay the section's
        // saved order. Retry only the requested move against refreshed geometry
        // below; full-section enforcement belongs to explicit layout passes.

        // A cancelled wait is no verdict; falling through would start a drag
        // racing whichever pass cancelled us.
        try Task.checkCancellation()

        // An icon can have a stale title key and the key the agent sorts by;
        // the first write lets positional resolution find the real one, so
        // retry once. Skip if nothing moved: the agent dropped the write.
        if !firstWait.barMoved {
            MenuBarItemManager.diagLog.warning(
                "Preferred-position write ignored by MenuBarAgent (bar never moved) for \(item.logString)"
            )
            _ = moveCircuitBreaker.note(.failedVerification)
            // An unnudged write was never given a chance to be observed,
            // the nudge is skipped while a section is revealed, which is
            // exactly when reveal-ordering writes are issued.
            if nudgeRan {
                noteMenuBarAgentIgnoredPreferredPositions()
            } else {
                MenuBarItemManager.diagLog.debug(
                    "Preferred-position write unverified (nudge skipped) for \(item.logString)"
                )
            }
            return false
        }

        if let refreshedItem = updated.first(where: {
            $0.tag.matchesIgnoringWindowID(item.tag)
        }),
            MenuBarPositionStoreProvider.forLayoutEdit.move(
                item: refreshedItem,
                to: destination,
                liveItems: updated,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        {
            commitPreferredPositionWrite(controller: appState?.menuBarManager.sectionController)
            // Same issue-time stamp as the first write above.
            moveActivity.noteMoveOperation()
            MenuBarItemManager.diagLog.debug(
                "Retrying preferred-position move after refreshed key resolution for \(item.logString)"
            )
            // Share the phase budget, but never leave the retry with zero polls:
            // if the first wait consumed the window the second write would be
            // issued and then never observed, which is worse than not retrying.
            let retryDeadline = max(
                deadline,
                ContinuousClock.now + Constants.MenuBarTuning.menuBarAgentResortPollInterval * 3
            )
            let retried = await waitForMenuBarAgentLayout(
                deadline: retryDeadline,
                enumerate: {
                    await MenuBarItem.getFreshMenuBarItemsForMove(priorityPIDs: Set([
                        item.ownerPID, item.sourcePID,
                        destination.targetItem.ownerPID, destination.targetItem.sourcePID,
                    ].compactMap(\.self)))
                },
                isSatisfied: destinationSatisfied
            )
            observationUnavailable = retried.observationUnavailable
            guard !observationUnavailable else {
                try Task.checkCancellation()
                return false
            }
            if destinationSatisfied(retried.items) {
                writeVerified = true
                moveActivity.noteMoveOperation()
                MenuBarItemManager.diagLog.info(
                    "Preferred-position move verified after key-resolution retry for \(item.logString) \(destination.logString)"
                )
                return true
            }
            try Task.checkCancellation()
        }

        MenuBarItemManager.diagLog.warning(
            "Preferred-position move did not verify for \(item.logString)"
        )
        return false
    }

    /// Records a preferred-position write and asks MenuBarAgent to consume it,
    /// in that order. Every self-write needs both, and the record must be in
    /// place before the nudge makes the agent re-read the table.
    func commitPreferredPositionWrite(controller: (any MenuBarSectionControlling)?) {
        controller?.notePreferredPositionsSelfWrite()
        requestMenuBarAgentPositionRefresh()
    }

    /// Makes MenuBarAgent consume a preferred-position write without restarting
    /// its compositor. Thaw's visible status item provides a safe layout seam.
    /// Returns whether a nudge was armed; see
    /// ControlItem/requestMenuBarAgentPositionRefresh().
    @discardableResult
    func requestMenuBarAgentPositionRefresh() -> Bool {
        // Every successful position-table write in this file funnels through
        // here, which makes it the one place to drop the memoized store read
        // so the enumeration that follows sees Thaw's own write.
        PositionStoreItemSource.invalidateStoreSnapshot()
        return appState?.menuBarManager.requestMenuBarAgentPositionRefresh() ?? false
    }

    /// The fallback move: a synthetic ⌘-drag from the item's center to the
    /// target edge. macOS 27 items share one compositor window, so only a
    /// cursor-hit-tested drag works; .maskCommand on the mouse events suffices.
    ///
    /// Verified by relative AX order, since the bar repacks items after a drop.
    private func moveItemViaCommandDrag(
        item: MenuBarItem,
        to destination: MoveDestination,
        maxAttempts: Int = 2,
        watchdogTimeout: Duration = .seconds(10),
        experimentalSystemItemHiding: Bool
    ) async throws {
        _ = moveCircuitBreaker.note(.syntheticDrag)
        var engine = SyntheticMoveEngine(
            eventSemaphore: eventSemaphore,
            makeEventSource: { try self.getEventSource() },
            enumerateItems: {
                // currentBounds matches on tag alone, so a recovery here would
                // start the drag on empty menu bar.
                await Self.dragGeometry(from: MenuBarItem.getMenuBarItems(option: .activeSpace))
            }
        )
        engine.cursorWatchdogTimeout = watchdogTimeout
        engine.prepareForAttempt = { attempt in
            // A retry follows a period of restored user input. Wait for idle
            // again, boundedly, then let the engine resolve fresh geometry.
            if attempt > 1 {
                guard await self.waitForUserToPauseInput(timeout: .seconds(1.5)) else {
                    try Task.checkCancellation()
                    throw EventError.cannotComplete
                }
            }
            try Task.checkCancellation()
        }
        engine.validateHIDInput = {
            // Recheck after enumeration, which can await a slow AX owner.
            guard self.appState?.isDraggingMenuBarItem != true,
                  !MouseHelpers.isButtonPressed()
            else { throw EventError.cannotComplete }
        }
        // This synthetic-drag path is the only mover, so without this stamp
        // applySavedLayout's 5s re-apply cooldown never arms and divergence
        // re-dispatches on every cache cycle instead.
        defer { moveActivity.noteMoveOperation() }
        // Total drag time against its budget. Each attempt costs about 1.4 s
        // plus settle and a walk, so 4 to 6 s means both attempts ran.
        let dragStarted = ContinuousClock.now
        defer {
            Self.diagLog.info(
                "command-drag \(item.logString) finished in \(ContinuousClock.now - dragStarted) (budget \(maxAttempts) attempt(s))"
            )
        }
        var attempts: [(address: SyntheticMoveEngine.DragAddress, landed: Bool)] = []
        engine.onAttemptResult = { address, landed in
            attempts.append((address, landed))
        }
        do {
            try await engine.move(
                item: item,
                to: destination,
                maxAttempts: maxAttempts,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
            moveMonitor.recordDragMove(
                item: item.logString,
                destination: destination.logString,
                attempts: attempts,
                duration: ContinuousClock.now - dragStarted,
                succeeded: true
            )
        } catch {
            moveMonitor.recordDragMove(
                item: item.logString,
                destination: destination.logString,
                attempts: attempts,
                duration: ContinuousClock.now - dragStarted,
                succeeded: false
            )
            throw error
        }
    }
}
