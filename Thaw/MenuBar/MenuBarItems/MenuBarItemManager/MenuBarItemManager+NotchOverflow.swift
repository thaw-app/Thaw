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

    /// Whether an item participates in the beside-notch budget as a managed
    /// item — i.e. Thaw can move it out of the way. Everything else (the clock,
    /// immovable system extras) is charged against the budget as fixed
    /// furniture instead.
    static nonisolated func isBudgetedManagedItem(_ item: MenuBarItem) -> Bool {
        (item.canBeHidden || item.tag == .visibleControlItem) && item.isMovable
    }

    /// Measures how much width the visible section actually has to the right of
    /// the notch.
    ///
    /// Shared by the profile-apply overflow phase and the continuous rebalance
    /// pass so both decide against identical geometry. Reads live item bounds
    /// only; the eject decision itself lives in
    /// ``LayoutSolver/planNotchOverflow(desiredFiltered:unmanagedUIDs:controlUIDs:sectionMap:uidWidths:availableWidth:)``.
    static func computeNotchOverflowBudget(
        items: [MenuBarItem],
        screen: NSScreen,
        notch: CGRect,
        spacingOffset: Int
    ) -> NotchOverflowBudget {
        let notchGap = MenuBarSection.notchGap
        // Available space: from notch gap to Control Center's left edge.
        let ccItem = items.first(where: { $0.tag == .controlCenter })
        let rightBoundary = ccItem.map(\.bounds.minX) ?? screen.frame.maxX
        var availableWidth = rightBoundary - (notch.maxX + notchGap)

        // NSStatusItemSpacing is recorded here for diagnostic logging
        // only. macOS bakes the spacing into each status item's frame
        // (verified empirically: item.bounds.width grows 1:1 with the
        // spacing value), so item.bounds.width and the Control Center
        // item's bounds.minX already account for it. Subtracting a
        // separate (count - 1) * spacing gap here used to double-count
        // the spacing and ejected items into hidden when the bar still
        // had room, most visibly at the macOS default of 16.
        let userSpacing = CGFloat(max(0, 16 + spacingOffset))

        // Subtract the layout footprint of items that occupy the visible area
        // but that Thaw cannot move: the Clock / date-time display, BentoBox
        // tray on systems that have it, and any immovable accessibility
        // extras. They take real estate in the same way managed items do but
        // are filtered out of the planner's uid list and would otherwise be
        // invisible to the budget check.
        // Transient system indicators (screen-recording AudioVideoModule,
        // FaceTime call indicator, ScreenCaptureUI overlay) appear and
        // disappear based on system events. Excluding them from the
        // budget keeps the overflow decision tied to the user's
        // permanent layout; otherwise, applying a profile while a
        // recording or call indicator is showing temporarily forces
        // a managed item out of visible, and that item won't come
        // back when the indicator goes away.
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
    /// A pass moves items, which recaches, which re-enters this path. The
    /// cooldown keeps that from becoming a loop when the geometry is right at
    /// the budget boundary and an ejected item's departure frees exactly enough
    /// room for the planner to want it back.
    private static let notchRebalanceCooldown: TimeInterval = 3

    /// Ejects items that no longer fit beside the notch into the hidden
    /// section, independently of any profile.
    ///
    /// Overflow used to exist only as a phase of ``applyProfileLayout``, so an
    /// item that arrived while no profile was active — or that belonged to no
    /// profile — was never ejected and simply grew the visible row across the
    /// notch. This pass runs off the cache-update tick instead, so a notched
    /// main display keeps its visible row inside the beside-notch budget at all
    /// times.
    ///
    /// When a profile *is* active the pass defers to
    /// ``scheduleProfileResort()``: a full apply re-runs the same planner while
    /// also honouring the saved order, so ejecting here would fight it. That
    /// handoff waits until the planner has actually found overflow — a pass
    /// with nothing to do must return without arming anything, or it drives
    /// the apply on every cache tick forever (#881).
    func rebalanceNotchOverflowIfNeeded(items: [MenuBarItem], controlItems: ControlItemPair) async {
        guard let appState else { return }
        guard appState.settings.advanced.enableMenuBarItemOverflow else { return }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "Notch overflow rebalance: skipping for provisional AX-frame correlation"
            )
            return
        }

        // Never fight another mover. Each of these owns the layout while it
        // runs and re-drives the cache when it finishes, so the next tick
        // picks up any overflow that is still outstanding.
        guard !isApplyingProfileLayout,
              !isRestoringItemOrder,
              !isInStartupSettling,
              !isBulkApplyInProgress
        else { return }

        // A temporarily-shown item is deliberately parked in visible for as
        // long as the user is interacting with it. Ejecting it would cancel
        // the reveal the user just asked for.
        guard temporarilyShownItemContexts.isEmpty else { return }

        // If the bar just refused synthetic drags in a profile apply, the
        // rebalance's own drags will fare no better — and each eject is a
        // full move() with its own cursor hijack. Without this gate the
        // rebalance fires on the very next cache tick after a failed apply,
        // trying 10–17 items one by one, each failing the same way, for tens
        // of seconds of dead pointer (#881, #907). The per-item failure-ledger
        // backoff cannot help because the rebalance's items are typically
        // different from the ones that failed in the batch.
        guard isAutomaticBulkApplyPermitted(caller: "Notch overflow rebalance", quietly: true) else {
            return
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
        else { return }

        // Mid-relocation between displays the item bounds straddle two screens
        // and the budget cannot be trusted. Same guard the persist path uses,
        // and the same input rule: only unparked items may feed it. Items left
        // of the hidden divider are parked at arbitrary negative x, which lands
        // inside a display positioned to the left of the main one and reads as
        // a permanent spread.
        //
        // The divider comes from the caller's ControlItemPair rather than a
        // lookup in items. Building that pair strips the hidden and
        // always-hidden control items out of the array it is given, and the
        // caller hands us that same stripped array, so searching it for
        // .hiddenControlItem finds nothing and the filter would silently pass
        // every parked item straight through.
        //
        // Frames come from CGDisplayBounds, not NSScreen.frame, for the same
        // reason as the other two call sites: item bounds are CoreGraphics
        // (top-left origin, y growing downward) while NSScreen.frame is AppKit
        // (bottom-left origin, y growing upward). Mixing them made every
        // containment test wrong off the main display, which on a vertically
        // stacked arrangement reads as no spread when the items really do
        // straddle two screens.
        let hiddenControlItemMinX = controlItems.hidden.bounds.minX
        let unparkedItems = items.filter { $0.bounds.minX >= hiddenControlItemMinX }
        guard !LayoutSolver.itemsSpanMultipleDisplays(
            itemCenters: unparkedItems.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) },
            screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        ) else { return }

        if let last = lastNotchRebalanceTimestamp,
           Date.now.timeIntervalSince(last) < Self.notchRebalanceCooldown
        {
            return
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

        // Every visible item counts as unmanaged here: with no profile active
        // none of them has a saved position to protect, and the tiered rule
        // degenerates to leftmost-first. With a profile active the tiering is
        // wrong, but this call is only read for whether the set is empty, and
        // that answer is the total footprint against the budget either way —
        // the tiers decide which items are chosen, not whether any are.
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
        guard !result.overflowUIDs.isEmpty else { return }

        // A profile apply is the better tool: it re-runs this same planner and
        // restores the saved order at the same time.
        //
        // This hands off only once the planner has found real overflow. The
        // handoff used to happen at the top of this method, before the
        // cooldown and before the budget was ever computed, so a bar with a
        // profile and a notch re-armed a full profile apply on every cache
        // tick — and each apply recaches, which runs this pass again. #881's
        // 08:41 log turned over 73 applies in four minutes on a bar that
        // never once overflowed: the pass returned before reaching
        // `computeNotchOverflowBudget`, so not one ejection was ever planned.
        // The apply moved six items per pass on unrelated grounds, each move
        // a synthetic drag that takes the cursor.
        if activeProfileLayout != nil {
            lastNotchRebalanceTimestamp = .now
            MenuBarItemManager.diagLog.info(
                "Notch overflow rebalance: deferring \(result.overflowUIDs.count) item(s) to the profile apply"
            )
            scheduleProfileResort()
            return
        }

        // Bounce-back guard. Every UID the planner wants to eject is one this
        // pass already ejected, yet they are back in visible — the move is not
        // sticking (an owner that re-adds its item to the right of the divider,
        // typically). Retrying on every cache tick would drag the bar forever,
        // so stand down until something else changes the set.
        if result.overflowUIDs.allSatisfy(notchOverflowEjectedUIDs.contains) {
            MenuBarItemManager.diagLog.debug(
                "Notch overflow rebalance: standing down; all \(result.overflowUIDs.count) candidate(s) were already ejected once"
            )
            return
        }

        lastNotchRebalanceTimestamp = .now
        MenuBarItemManager.diagLog.info(
            """
            Notch overflow rebalance: ejecting \(result.overflowUIDs.count) item(s) to hidden; \
            \(budget.logString)
            """
        )

        // Leftmost-first, so each ejected item lands deeper in hidden than the
        // one before it and the surviving visible order is preserved.
        for uid in result.overflowUIDs {
            guard let item = items.first(where: { $0.uniqueIdentifier == uid }) else { continue }
            // The bounce-back guard above only covers ejections that landed.
            // A candidate whose eject keeps failing would otherwise be
            // re-dragged on every windowID change against unchanged geometry
            // (#900) — the ledger's growing per-item window bounds that the
            // same way it bounds the profile-layout moves.
            if failureLedger.isUnderBackoff(key: uid) {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow rebalance: \(uid) under move-failure backoff, skipping"
                )
                continue
            }
            do {
                try await move(item: item, to: .leftOfItem(controlItems.hidden))
                notchOverflowEjectedUIDs.insert(uid)
                failureLedger.recordSuccess(for: item)
            } catch {
                if !Self.moveAlreadyFiledFailure(for: error) {
                    failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                }
                MenuBarItemManager.diagLog.error(
                    "Notch overflow rebalance: failed to eject \(item.logString): \(error)"
                )
            }
        }
    }
}
