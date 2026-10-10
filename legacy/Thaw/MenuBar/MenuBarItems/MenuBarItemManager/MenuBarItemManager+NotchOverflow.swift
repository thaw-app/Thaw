//
//  MenuBarItemManager+NotchOverflow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Notch Overflow

extension MenuBarItemManager {
    /// The measured beside-notch width budget for the visible section.
    struct NotchOverflowBudget {
        /// Usable width between the notch gap and the right boundary, with the
        /// footprint of unmanageable items already subtracted.
        var availableWidth: CGFloat
        /// The left edge of Control Center, or the screen's right edge when
        /// Control Center cannot be located.
        var rightBoundary: CGFloat

        var logString: String
    }

    /// Whether Thaw can move the item out of the way. Everything else (the clock,
    /// immovable system extras) is charged against the budget as fixed width.
    static nonisolated func isBudgetedManagedItem(_ item: MenuBarItem) -> Bool {
        (item.canBeHidden || item.tag == .visibleControlItem) && item.isMovable
    }

    /// Measures how much width the visible section has right of the notch.
    ///
    /// Shared by profile apply and the continuous rebalance so both see the
    /// same geometry. The eject decision lives in
    /// ``LayoutSolver/planNotchOverflow(desiredFiltered:unmanagedUIDs:controlUIDs:sectionMap:uidWidths:availableWidth:)``.
    static func computeNotchOverflowBudget(
        items: [MenuBarItem],
        screen: NSScreen,
        notch: CGRect,
        spacingOffset: Int
    ) -> NotchOverflowBudget {
        let notchGap = MenuBarSection.notchGap
        let ccItem = items.first(where: { $0.tag == .controlCenter })
        let rightBoundary = ccItem.map(\.bounds.minX) ?? screen.frame.maxX
        var availableWidth = rightBoundary - (notch.maxX + notchGap)

        // Logging only. macOS bakes NSStatusItemSpacing into each item's frame
        // (width grows 1:1 with it), so subtracting it again double-counts.
        let userSpacing = CGFloat(max(0, 16 + spacingOffset))

        // Subtract items Thaw can't move (clock, BentoBox, immovable extras);
        // the planner's uid list doesn't include them.
        // Transient indicators (recording, FaceTime, ScreenCaptureUI) are excluded,
        // or a profile applied during a call ejects an item that never comes back.
        let transientTags: [MenuBarItemTag] = [
            .audioVideoModule,
            .faceTime,
            .screenCaptureUI,
            .gameMode,
        ]
        var unmanagedFootprint: CGFloat = 0
        var unmanagedCount = 0
        var unmanagedBreakdown = [String]()
        for item in items where !isBudgetedManagedItem(item) {
            guard item.bounds.minX >= notch.maxX,
                  item.bounds.maxX <= rightBoundary
            else { continue }
            if transientTags.contains(where: {
                $0.namespace == item.tag.namespace && $0.title == item.tag.title
            }) || item.isTransientControlCenterItem || item.hasProvisionalIdentity {
                continue
            }
            unmanagedFootprint += item.bounds.width
            unmanagedCount += 1
            unmanagedBreakdown.append("\(item.uniqueIdentifier)=\(item.bounds.width)")
        }
        availableWidth -= unmanagedFootprint

        return NotchOverflowBudget(
            availableWidth: availableWidth,
            rightBoundary: rightBoundary,
            logString: """
            screen.maxX=\(screen.frame.maxX) notch=[\(notch.minX)…\(notch.maxX)] \
            rightBoundary=\(rightBoundary) availableWidth=\(availableWidth) \
            userSpacing=\(userSpacing) unmanagedCount=\(unmanagedCount) \
            unmanagedFootprint=\(unmanagedFootprint) \
            unmanagedBreakdown=[\(unmanagedBreakdown.joined(separator: ", "))]
            """
        )
    }

    /// Minimum interval between two continuous rebalance passes.
    ///
    /// A pass moves items, which recaches and re-enters this path. Without the
    /// cooldown it loops when an ejection frees just enough room to want the item back.
    private static let notchRebalanceCooldown: TimeInterval = 3

    /// Ejects items that no longer fit beside the notch into the hidden
    /// section, independently of any profile.
    ///
    /// Runs off the cache-update tick, so items outside any profile are ejected too.
    ///
    /// With an active profile it defers to ``scheduleProfileResort()``, but
    /// only once overflow is found; arming it with nothing to do re-runs the
    /// apply on every cache tick forever (#881).
    func rebalanceNotchOverflowIfNeeded(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        shouldBeginMove: (@MainActor () -> Bool)? = nil
    ) async -> CacheDrivenMoveOutcome {
        guard let appState else { return .noAttempt }
        guard appState.settings.advanced.enableMenuBarItemOverflow else { return .noAttempt }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "Notch overflow rebalance: skipping for provisional AX-frame correlation"
            )
            return .noAttempt
        }

        // Never fight another mover; each recaches when done, so the next tick
        // picks up leftover overflow.
        guard !isApplyingProfileLayout,
              !isRestoringItemOrder,
              !isInStartupSettling,
              !isBulkApplyInProgress
        else { return .noAttempt }

        // Ejecting a temporarily-shown item would cancel the reveal the user asked for.
        guard temporarilyShownItemContexts.isEmpty else { return .noAttempt }

        // If the bar just refused a profile apply's drags, these fail too, each
        // hijacking the cursor, for tens of seconds (#881, #907). The per-item
        // ledger can't help: these are usually different items.
        guard isAutomaticBulkApplyPermitted(caller: "Notch overflow rebalance", quietly: true) else {
            return .noAttempt
        }

        let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar
        guard LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: true,
            activeScreenKnown: activeMenuBarScreen != nil,
            activeHasNotch: activeMenuBarScreen?.hasNotch ?? false,
            activeIsMainDisplay: activeMenuBarScreen?.displayID == CGMainDisplayID()
        ),
            let screen = activeMenuBarScreen,
            let notch = screen.frameOfNotch
        else { return .noAttempt }

        // Mid-relocation the bounds straddle two screens and the budget can't be
        // trusted. Only unparked items count: parked items sit at negative x,
        // which can land on a display left of main and read as a permanent spread.
        //
        // The divider comes from controlItems because `items` has the control
        // items stripped; searching it would find nothing and pass every parked item.
        //
        // CGDisplayBounds, not NSScreen.frame: item bounds use top-left origin.
        // Mixing them breaks containment off the main display.
        let hiddenControlItemMinX = controlItems.hidden.bounds.minX
        let unparkedItems = items.filter { $0.bounds.minX >= hiddenControlItemMinX }
        guard !LayoutSolver.itemsSpanMultipleDisplays(
            itemCenters: unparkedItems.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) },
            screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        ) else { return .noAttempt }

        if let last = lastNotchRebalanceTimestamp,
           Date.now.timeIntervalSince(last) < Self.notchRebalanceCooldown
        {
            return .noAttempt
        }

        let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
        let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

        // Live flat order, grouped by section, in the shape planNotchOverflow
        // expects: visible items, hidden control item, hidden items,
        // always-hidden control item, always-hidden items.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        var bySection: [MenuBarSection.Name: [MenuBarItem]] = [:]
        for item in items where Self.isBudgetedManagedItem(item) && !item.isControlItem {
            guard let section = context.findSection(for: item) else { continue }
            bySection[section, default: []].append(item)
        }
        for key in bySection.keys {
            // Tie-broken sort: this order is persisted as the layout of
            // record, so items sharing a minX mid-reflow must not land in a
            // different relative order from one snapshot to the next.
            bySection[key] = MenuBarItem.sortByLeadingEdgeThenIdentifier(bySection[key] ?? [])
        }

        var flat = (bySection[.visible] ?? []).map(\.uniqueIdentifier)
        let visibleUIDs = flat
        flat.append(hiddenCtrlUID)
        flat.append(contentsOf: (bySection[.hidden] ?? []).map(\.uniqueIdentifier))
        if let ahCtrlUID {
            flat.append(ahCtrlUID)
            flat.append(contentsOf: (bySection[.alwaysHidden] ?? []).map(\.uniqueIdentifier))
        }

        let budget = Self.computeNotchOverflowBudget(
            items: items,
            screen: screen,
            notch: notch,
            spacingOffset: appState.spacingManager.offset
        )
        var availableWidth = budget.availableWidth

        let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier
        var uidWidths = [String: CGFloat]()
        for item in items where visibleUIDs.contains(item.uniqueIdentifier) {
            uidWidths[item.uniqueIdentifier] = item.bounds.width
        }
        if let visibleCtrlUID,
           let chevron = items.first(where: { $0.uniqueIdentifier == visibleCtrlUID }),
           chevron.bounds.minX >= notch.maxX,
           chevron.bounds.maxX <= budget.rightBoundary
        {
            availableWidth -= chevron.bounds.width
        }

        // All visible items count as unmanaged, which makes the rule leftmost-first.
        // With a profile active only emptiness is read, which the tiers don't affect.
        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: flat,
            unmanagedUIDs: visibleUIDs.filter { $0 != visibleCtrlUID },
            controlUIDs: ControlUIDs(
                visible: visibleCtrlUID,
                hidden: hiddenCtrlUID,
                alwaysHidden: ahCtrlUID
            ),
            sectionMap: [:],
            uidWidths: uidWidths,
            availableWidth: availableWidth
        )
        guard !result.overflowUIDs.isEmpty else { return .noAttempt }

        // A profile apply re-runs this planner and restores the saved order.
        // Hand off only after real overflow is found; handing off earlier
        // re-armed an apply on every cache tick (#881).
        if activeProfileLayout != nil {
            lastNotchRebalanceTimestamp = .now
            MenuBarItemManager.diagLog.info(
                "Notch overflow rebalance: deferring \(result.overflowUIDs.count) item(s) to the profile apply"
            )
            scheduleProfileResort()
            return .noAttempt
        }

        // Every item to eject was already ejected and came back, so the move
        // isn't sticking. Stand down until the set changes.
        if result.overflowUIDs.allSatisfy(notchOverflowEjectedUIDs.contains) {
            MenuBarItemManager.diagLog.debug(
                "Notch overflow rebalance: standing down; all \(result.overflowUIDs.count) candidate(s) were already ejected once"
            )
            return .noAttempt
        }

        lastNotchRebalanceTimestamp = .now
        MenuBarItemManager.diagLog.info(
            """
            Notch overflow rebalance: ejecting \(result.overflowUIDs.count) item(s) to hidden; \
            \(budget.logString)
            """
        )

        // The cache snapshot owns the first move. Each accepted attempt then
        // adopts its timestamp before releasing moveGate, so later moves in
        // this batch accept its own work but reject an intervening user move.
        var batchMovePreflight = BatchMovePreflightState()
        var didAcceptMoveAttempt = false
        var didAcceptCurrentMove = false
        var didCompleteMove = false
        var didFailAcceptedMove = false
        func shouldBeginBatchMove() -> Bool {
            let shouldBegin = batchMovePreflight.shouldBeginMove(
                currentTimestamp: lastMoveOperationTimestamp,
                initialPreflight: {
                    shouldBeginMove?() ?? true
                }
            )
            if shouldBegin {
                didAcceptMoveAttempt = true
                didAcceptCurrentMove = true
            }
            return shouldBegin
        }
        func didFinishBatchMove() {
            batchMovePreflight.recordMoveGateExit(
                timestamp: lastMoveOperationTimestamp
            )
        }

        // Leftmost-first, so each ejected item lands deeper in hidden than the
        // one before it and the surviving visible order is preserved.
        for uid in result.overflowUIDs {
            guard let item = items.first(where: { $0.uniqueIdentifier == uid }) else { continue }
            // The bounce-back guard only covers ejections that landed. Without
            // the ledger backoff a failing eject is re-dragged on every windowID change (#900).
            if failureLedger.isUnderBackoff(key: uid) {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow rebalance: \(uid) under move-failure backoff, skipping"
                )
                continue
            }
            didAcceptCurrentMove = false
            do {
                try await move(
                    item: item,
                    to: .leftOfItem(controlItems.hidden),
                    options: .init(
                        shouldBegin: shouldBeginBatchMove,
                        didFinishWhileHoldingGate: didFinishBatchMove
                    )
                )
                notchOverflowEjectedUIDs.insert(uid)
                failureLedger.recordSuccess(for: item)
                didCompleteMove = true
            } catch EventError.moveSuperseded {
                didFailAcceptedMove = didFailAcceptedMove || didAcceptCurrentMove
                MenuBarItemManager.diagLog.debug(
                    "Stopping stale notch-overflow rebalance before moving \(item.logString)"
                )
                if didFailAcceptedMove {
                    return .failedAttempt
                }
                return didCompleteMove ? .completed : .noAttempt
            } catch {
                didFailAcceptedMove = didFailAcceptedMove || didAcceptCurrentMove
                if !Self.moveAlreadyFiledFailure(for: error) {
                    failureLedger.recordFailure(for: item, kind: ledgerFailureKind(for: error, item: item))
                }
                MenuBarItemManager.diagLog.error(
                    "Notch overflow rebalance: failed to eject \(item.logString): \(error)"
                )
                await reportAutomaticMoveFailure(
                    of: item,
                    to: .leftOfItem(controlItems.hidden),
                    expectedSection: .hidden,
                    error: error,
                    source: "notch overflow management"
                )
            }
        }
        if didFailAcceptedMove {
            return .failedAttempt
        }
        if didCompleteMove {
            return .completed
        }
        return didAcceptMoveAttempt ? .failedAttempt : .noAttempt
    }
}
