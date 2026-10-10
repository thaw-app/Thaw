//
//  MenuBarItemManager+CachePublish.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Cache Publish

extension MenuBarItemManager {
    /// Caches the items without checking the control item order.
    func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?,
        suppressAutomaticMoves: Bool,
        suppressSavedOrderPersistence: Bool,
        forcePersistSavedOrder: Bool,
        snapshotIsCurrent: () -> Bool
    ) async {
        guard snapshotIsCurrent() else { return }
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        var validCount = 0
        var invalidCount = 0
        var noSectionCount = 0

        // macOS can briefly report two windows for one item after a move.
        // Keep the first, which is the rightmost.
        var seenTags = Set<MenuBarItemTag>()

        for item in items where context.isValidForCaching(item) {
            guard seenTags.insert(item.tag).inserted else {
                MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
                continue
            }

            validCount += 1
            if item.sourcePID == nil {
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.warning("Missing sourcePID for \(item.logString)")
            }

            let matchingContext: TemporarilyShownItemContext? = {
                // Exact tag match, including windowID for non-system items.
                if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                    return temp
                }
                // Tag and PID match, only for an item physically in visible that belongs elsewhere.
                if let temp = temporarilyShownItemContexts.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        $0.sourcePID == (item.sourcePID ?? item.ownerPID)
                }),
                    context.findSection(for: item) == .visible,
                    temp.originalSection != .visible
                {
                    return temp
                }
                return nil
            }()

            if let matchingContext {
                // Cached at their return destinations once the rest are placed.
                context.temporarilyShownItems.append((item, matchingContext.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            noSectionCount += 1
            let currentBounds = item.liveBounds
            if currentBounds.origin.x == -1 {
                MenuBarItemManager.diagLog.warning(
                    "Skipping \(item.logString); blocked (x=-1), will retry on next cache tick"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds)), assigning to hidden"
                )
                context.cache[.hidden].append(item)
            }
        }

        for item in items where !context.isValidForCaching(item) {
            invalidCount += 1
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(validCount) valid, \(invalidCount) invalid (filtered), \(noSectionCount) couldn't find section, \(context.temporarilyShownItems.count) temporarily shown")

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        let cacheChanged = itemCache != context.cache

        // Discard a pass whose divider geometry disagrees with the section's
        // logical state. Keeping the previous cache costs one cycle; accepting
        // the mixture reclassifies a whole section (#851).
        if Self.shouldEvaluateSavedOrderPersistence(
            cacheChanged: cacheChanged,
            forcePersistSavedOrder: forcePersistSavedOrder
        ),
            !itemCache.managedItems.isEmpty,
            let section = await midTransitionSection(in: context)
        {
            MenuBarItemManager.diagLog.debug(
                "Not updating menu bar item cache: \(section.logString) is mid expand/collapse, keeping last-known-good cache"
            )
            return
        }

        // midTransitionSection can suspend while a user move makes this reading obsolete.
        guard snapshotIsCurrent() else { return }

        // Without the always-hidden divider, findSection folds always-hidden into
        // hidden; persisting that made #849 permanent.
        let alwaysHiddenSectionResolved = LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: context.controlItems.alwaysHidden != nil,
            isAlwaysHiddenSectionEnabled: appState?.menuBarManager
                .section(withName: .alwaysHidden)?.isEnabled ?? false
        )

        // CGDisplayBounds, not NSScreen.frame: item bounds are in flipped CG space.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }

        // A zero-width hidden span classifies on-screen items as visible (#795).
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
            alwaysHiddenControlItemMaxX: context.alwaysHiddenControlItemBounds.first?.maxX,
            savedHiddenItemCount: savedSectionOrder[sectionKey(for: .hidden)]?.count ?? 0,
            liveHiddenItemCount: context.cache[.hidden].count,
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: MenuBarSection.Name.allCases.flatMap { section in
                    context.cache[section].map(\.bounds)
                },
                hiddenControlItemMinX: context.hiddenControlItemBounds.minX,
                screenFrames: screenFrames
            )
        )

        if !suppressAutomaticMoves,
           recoverCollapsedHiddenSectionIfNeeded(
               hiddenSectionHasRoom: hiddenSectionHasRoom,
               controlItems: context.controlItems,
               // Dividers excluded: with only them to place, a rebuild strands nothing.
               managedItemCount: context.cache.managedItems.count(where: { !$0.isControlItem })
           )
        {
            return
        }

        guard Self.shouldEvaluateSavedOrderPersistence(
            cacheChanged: cacheChanged,
            forcePersistSavedOrder: forcePersistSavedOrder
        ) else {
            MenuBarItemManager.diagLog.debug("Not updating menu bar item cache, as items haven't changed")
            // Still counts: settling's early exit needs these stable no-op reads.
            completedCacheCycles += 1
            return
        }

        // Read before it's overwritten: the save gate checks for a display change (#958).
        let previousCacheDisplayID = itemCache.displayID

        if cacheChanged {
            itemCache = context.cache

            // Lets the next launch label items before its source-PID scan lands (#956).
            MenuBarItemNameMemory.remember(itemCache.managedItems)
        } else {
            MenuBarItemManager.diagLog.debug(
                "Menu bar item cache is unchanged; evaluating saved-order persistence for a validated Layout-editor move"
            )
        }

        // A stuck flag would block saves after manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, Date().timeIntervalSince(timestamp) > 10 {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        let hasPendingDivergence = pendingDivergenceObservedAt != nil

        // Mirrors applySavedLayout's cooldown, or a cycle can save a bar nobody
        // arranged (#958). User moves are exempt: the save must win so the
        // restore doesn't later revert the drag as drift.
        let isWithinMoveCooldown = lastMoveOperationOccurred(within: .seconds(5)) &&
            !Self.saveCooldownExemptForUserMove(
                lastMoveOperationTimestamp: lastMoveOperationTimestamp,
                lastUserMoveOperationTimestamp: lastUserMoveOperationTimestamp
            )

        // A relocation in progress. A nil on either side is just the first cycle.
        let menuBarDisplayChanged: Bool = if let previousCacheDisplayID,
                                             let currentDisplayID = context.cache.displayID
        {
            previousCacheDisplayID != currentDisplayID
        } else {
            false
        }

        // Saving a half-applied batch makes the bar drift further every retry (#900).
        if !suppressSavedOrderPersistence,
           context.controlItems.canRepositionControlItems,
           LayoutSolver.shouldPersistSavedOrder(
               LayoutSolver.SavedOrderGate(
                   isRestoringItemOrder: isRestoringItemOrder,
                   isResettingLayout: isResettingLayout,
                   isInStartupSettling: isInStartupSettling,
                   isApplyingProfileLayout: isApplyingProfileLayout,
                   temporarilyShownItemContextsIsEmpty: temporarilyShownItemContexts.isEmpty,
                   alwaysHiddenSectionResolved: alwaysHiddenSectionResolved,
                   hiddenSectionHasRoom: hiddenSectionHasRoom,
                   hasPendingDivergence: hasPendingDivergence,
                   hasUnfinishedMoveBatch: hasUnfinishedMoveBatch,
                   isWithinMoveCooldown: isWithinMoveCooldown,
                   menuBarDisplayChanged: menuBarDisplayChanged
               )
           )
        {
            // Items at x=-1 are in a transient blocked state.
            let hasBlockedItems = MenuBarSection.Name.allCases.contains { section in
                context.cache[section].contains { item in
                    let bounds = item.liveBounds
                    return bounds.origin.x == -1
                }
            }
            // Items straddling two displays mean a relocation mid-flight, and macOS
            // un-hides items as it moves them. Saving now bakes that in.
            //
            // Visible only: parked items sit at negative x, which a display left of
            // main owns, so they'd always read as a second screen.
            let itemCenters = context.cache[.visible].map {
                CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)
            }
            let spansDisplays = LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: itemCenters,
                screenFrames: screenFrames
            )
            if hasBlockedItems {
                MenuBarItemManager.diagLog.warning(
                    "Skipping saveSectionOrder; blocked items detected (x=-1), will retry on next cache tick"
                )
            } else if spansDisplays {
                MenuBarItemManager.diagLog.warning(
                    "Skipping saveSectionOrder; menu bar items span multiple displays (relocation in progress)"
                )
            } else {
                saveSectionOrder(from: context.cache)
            }
        } else if suppressSavedOrderPersistence {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; this cache refresh follows a failed automatic move attempt"
            )
        } else if !context.controlItems.canRepositionControlItems {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; control items resolved only by provisional AX-frame correlation"
            )
        } else if !alwaysHiddenSectionResolved {
            // Separate warning: this one silently rewrites the layout when wrong (#849).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; always-hidden divider unresolved while its section is enabled"
            )
        } else if !hiddenSectionHasRoom {
            // A geometry fault, kept greppable apart from the one above.
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; hidden section has zero width between the dividers (hidden.minX=\(context.hiddenControlItemBounds.minX) windowID=\(context.controlItems.hidden.windowID), alwaysHidden.maxX=\(context.alwaysHiddenControlItemBounds.first?.maxX.description ?? "nil") windowID=\(context.controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
        } else if hasPendingDivergence {
            // applySavedLayout is waiting for a second divergence reading. This
            // cache may be transient (e.g. a space switch re-exposing hidden items) (#736).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; layout divergence pending confirmation (applySavedLayout has not yet restored the cached layout)"
            )
        } else if isWithinMoveCooldown {
            // A run of these means the bar never settles long enough to save (#958).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; within the 5s move cooldown that applySavedLayout also honours"
            )
        } else if menuBarDisplayChanged {
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; menu bar moved display since the standing cache (\(previousCacheDisplayID.map { "\($0)" } ?? "nil") -> \(context.cache.displayID.map { "\($0)" } ?? "nil")), relocation in progress"
            )
        } else if hasUnfinishedMoveBatch {
            // A run of these means the apply keeps failing and the layout never takes (#900).
            MenuBarItemManager.diagLog.warning(
                "Skipping saveSectionOrder; the last bulk apply left planned moves unenacted, so the current arrangement is partial"
            )
        }
        if cacheChanged {
            MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")
        }
        completedCacheCycles += 1
    }

    /// A validated Layout-editor move may already have published its geometry,
    /// so an identical cache must not stop its final refresh here.
    static nonisolated func shouldEvaluateSavedOrderPersistence(
        cacheChanged: Bool,
        forcePersistSavedOrder: Bool
    ) -> Bool {
        cacheChanged || forcePersistSavedOrder
    }

    /// Returns the hideable section whose divider geometry contradicts its
    /// logical state, or nil when both sections agree.
    ///
    /// See isMidSectionTransition(dividerWidth:isSectionCollapsed:) for why
    /// the two can disagree.
    private func midTransitionSection(in context: CacheContext) async -> MenuBarSection.Name? {
        var widths: [(MenuBarSection.Name, CGFloat)] = [
            (.hidden, context.hiddenControlItemBounds.width),
        ]
        if let alwaysHiddenBounds = context.alwaysHiddenControlItemBounds.first {
            widths.append((.alwaysHidden, alwaysHiddenBounds.width))
        }

        let mismatch = await MainActor.run { [weak self] () -> MenuBarSection.Name? in
            guard let menuBarManager = self?.appState?.menuBarManager else {
                return nil
            }
            return widths.first { name, width in
                guard
                    let section = menuBarManager.section(withName: name),
                    section.isEnabled
                else {
                    return false
                }
                return MenuBarItemManager.isMidSectionTransition(
                    dividerWidth: width,
                    isSectionCollapsed: section.isHidden
                )
            }?.0
        }

        guard let mismatch else {
            midTransitionSkipStreak = 0
            return nil
        }

        midTransitionSkipStreak += 1
        guard midTransitionSkipStreak <= MenuBarItemManager.maxMidTransitionSkips else {
            MenuBarItemManager.diagLog.warning(
                "midTransitionSection: \(mismatch.logString) still mid expand/collapse after \(midTransitionSkipStreak) passes, accepting this one"
            )
            midTransitionSkipStreak = 0
            return nil
        }

        return mismatch
    }
}
