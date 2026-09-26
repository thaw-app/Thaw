//
//  MenuBarItemManager+SavedLayoutApply.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

extension MenuBarItemManager {
    static nonisolated func baseIdentifier(forSavedIdentifier identifier: String) -> String {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return identifier }
        return "\(parts[0]):\(parts[1])"
    }

    static nonisolated func savedLayoutSectionLookup(
        savedSectionOrder: [String: [String]]
    ) -> (
        exact: [String: MenuBarSection.Name],
        unambiguousBase: [String: MenuBarSection.Name]
    ) {
        var exactSections = [String: Set<MenuBarSection.Name>]()
        var baseSections = [String: Set<MenuBarSection.Name>]()

        for (sectionKey, identifiers) in savedSectionOrder {
            guard let section = persistedSectionName(for: sectionKey) else { continue }
            for identifier in identifiers {
                exactSections[identifier, default: []].insert(section)
                baseSections[baseIdentifier(forSavedIdentifier: identifier), default: []].insert(section)
            }
        }

        let exact = exactSections.compactMapValues { sections in
            sections.count == 1 ? sections.first : nil
        }
        let unambiguousBase = baseSections.compactMapValues { sections in
            sections.count == 1 ? sections.first : nil
        }

        return (exact, unambiguousBase)
    }

    /// Whether any saved, movable item is in a different section than saved.
    ///
    /// Catches drift that keeps windowIDs (Stage Manager, third-party tools,
    /// macOS respawning the bar). Straddling items are ignored during show/hide
    /// animations; base-identifier fallback applies only when all saved
    /// instances share one section.
    private func currentLayoutDivergesFromSaved(
        items: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> Bool {
        // Ejected items diverge by design and would re-dispatch every cycle. Skip
        // them only with the feature on, a notched active display, and the item in hidden.
        let overflowSkipActive = (appState?.settings.advanced.enableMenuBarItemOverflow ?? false)
            && ((NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.hasNotch ?? false)
        let knownBaseIdentifiers = Set(items.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(items.map(\.uniqueIdentifier))
        // With no triggers, isTriggerProtected goes quadratic on a per-cycle path.
        let hasTriggerProtectedItems = !triggerControlledItemIdentifiers.isEmpty

        return Self.layoutDivergesFromSaved(
            candidates: items
                .filter {
                    !$0.isControlItem
                        && $0.canBeHidden
                        && $0.isMovable
                        && !(hasTriggerProtectedItems && Self.isTriggerProtected(
                            $0.uniqueIdentifier,
                            by: triggerControlledItemIdentifiers,
                            knownBaseIdentifiers: knownBaseIdentifiers,
                            knownLiveIdentifiers: knownLiveIdentifiers
                        ))
                }
                .map { item in
                    DivergenceCandidate(
                        tagIdentifier: item.tag.tagIdentifier,
                        uniqueIdentifier: item.uniqueIdentifier,
                        bounds: item.bounds
                    )
                },
            sectionLookup: Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder),
            hiddenBounds: controlItems.hidden.bounds,
            alwaysHiddenBounds: controlItems.alwaysHidden?.bounds,
            overflowExemptUIDs: overflowSkipActive ? notchOverflowEjectedUIDs : [],
            activelyShownTags: Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))
        )
    }

    /// One item of a bar reading, reduced to what the divergence rule reads.
    struct DivergenceCandidate {
        let tagIdentifier: String
        let uniqueIdentifier: String
        let bounds: CGRect
    }

    /// Whether any item sits in a different section than savedSectionOrder
    /// records for it.
    ///
    /// applySavedLayout's drift trigger. Exemptions are passed in to keep it pure:
    ///
    /// - overflowExemptUIDs: notch ejections; empty unless the feature is on
    ///   and the active display is notched.
    /// - activelyShownTags: temporarily shown items. Treating them as drift can
    ///   drag one home under the menu the user just opened (#924).
    static nonisolated func layoutDivergesFromSaved(
        candidates: [DivergenceCandidate],
        sectionLookup: (exact: [String: MenuBarSection.Name], unambiguousBase: [String: MenuBarSection.Name]),
        hiddenBounds: CGRect,
        alwaysHiddenBounds: CGRect?,
        overflowExemptUIDs: Set<String>,
        activelyShownTags: Set<String>
    ) -> Bool {
        guard !sectionLookup.exact.isEmpty || !sectionLookup.unambiguousBase.isEmpty else { return false }

        let hiddenMinX = hiddenBounds.minX
        let hiddenMaxX = hiddenBounds.maxX
        let ahBounds = alwaysHiddenBounds

        for candidate in candidates {
            guard !activelyShownTags.contains(candidate.tagIdentifier) else { continue }
            let identifier = candidate.uniqueIdentifier
            let baseID = Self.baseIdentifier(forSavedIdentifier: identifier)
            guard let expectedSection = sectionLookup.exact[identifier]
                ?? sectionLookup.unambiguousBase[baseID]
            else {
                continue
            }

            let currentSection: MenuBarSection.Name? = if candidate.bounds.minX >= hiddenMaxX {
                .visible
            } else if let ahBounds, candidate.bounds.maxX <= ahBounds.minX {
                .alwaysHidden
            } else if let ahBounds, candidate.bounds.minX >= ahBounds.maxX, candidate.bounds.maxX <= hiddenMinX {
                .hidden
            } else if ahBounds == nil, candidate.bounds.maxX <= hiddenMinX {
                .hidden
            } else {
                nil
            }

            guard let currentSection else { continue }
            if currentSection == .hidden, overflowExemptUIDs.contains(identifier) {
                continue
            }
            if currentSection != expectedSection {
                return true
            }
        }
        return false
    }

    /// Whether a windowID-set difference is a real change or just the menu bar
    /// switching displays.
    ///
    /// With separate Spaces, a display switch makes the old display's windows
    /// read as missing. Treating that as a quit re-sorts on every focus change.
    static nonisolated func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool {
        guard !previous.isEmpty else { return false }
        // Only when both displays are known and differ.
        if let previousDisplayID, let currentDisplayID, previousDisplayID != currentDisplayID {
            return false
        }
        return !previous.isSubset(of: current)
    }

    /// Whether enough menu bar items are missing a resolved source PID that
    /// bulk-applying the saved layout would act on unmatchable identities.
    ///
    /// A failed XPC connection leaves most items with a nil sourcePID. Some
    /// system items are always nil, so only a majority counts; tiny sets are exempt.
    static nonisolated func majorityOfSourcePIDsUnresolved(unresolvedCount: Int, itemCount: Int) -> Bool {
        itemCount >= 4 && unresolvedCount * 2 > itemCount
    }

    /// Narrows a saved order to the identifiers whose live item has a
    /// resolved sourcePID, for the early apply that runs while resolution is
    /// still in progress.
    ///
    /// A dropped identifier stays untouched, since planLCSMoveSequence only moves
    /// items in both sequences. Empty section keys are kept.
    ///
    /// Exact match: a base match could admit an unresolved sibling (Item-0:2).
    static nonisolated func savedOrderRestrictedToResolvedIdentities(
        savedSectionOrder: [String: [String]],
        resolvedIdentifiers: Set<String>
    ) -> [String: [String]] {
        savedSectionOrder.mapValues { identifiers in
            identifiers.filter(resolvedIdentifiers.contains)
        }
    }

    /// Decides whether a divergence observation should trigger the apply.
    ///
    /// A wide app menu can shift status items for a moment, so divergence must
    /// be seen on two consecutive cycles (#723).
    ///
    /// - Parameters:
    ///   - divergedNow: The result of the current cycle's divergence check.
    ///   - pendingSince: The timestamp of a prior unconfirmed observation, if
    ///     one is armed.
    ///   - now: The current time.
    ///   - staleness: How long an armed observation can still be confirmed.
    ///     A stale arm is treated as a fresh first observation.
    /// - Returns: Whether this confirms the divergence, and the pending
    ///   state for the next cycle.
    static nonisolated func confirmedDivergence(
        divergedNow: Bool,
        pendingSince: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        staleness: Duration = .seconds(30)
    ) -> (confirmed: Bool, newPendingSince: ContinuousClock.Instant?) {
        guard divergedNow else {
            return (false, nil)
        }
        guard let pendingSince else {
            return (false, now)
        }
        guard now - pendingSince <= staleness else {
            // Too old to confirm against; re-arm.
            return (false, now)
        }
        return (true, nil)
    }

    /// The previous cache cycle's state that applySavedLayout diffs
    /// the current bar against to decide whether a restore is warranted.
    nonisolated struct PreviousCacheCycle {
        var windowIDs: [CGWindowID]
        var displayID: CGDirectDisplayID?
        var ccGenericWindowIDs: Set<CGWindowID> = []
    }

    /// Re-applies the saved layout through applyProfileLayout with source .savedOrder.
    ///
    /// Returns true if dispatched; the apply drives its own recache, so the
    /// caller should stop its cycle. False when an entry guard rejects it.
    func applySavedLayout(
        items: [MenuBarItem],
        previousCycle: PreviousCacheCycle,
        controlItems: ControlItemPair,
        currentDisplayID: CGDirectDisplayID? = nil,
        bypassMoveCooldown: Bool = false,
        resolvedIdentitiesOnly: Bool = false,
        shouldBegin: (@MainActor () -> Bool)? = nil
    ) async -> Bool {
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping superseded cache snapshot")
            return false
        }
        // Each guard logs a distinct reason for bug reports. Cheap checks first.
        guard !savedSectionOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, savedSectionOrder is empty")
            return false
        }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping for provisional AX-frame correlation"
            )
            return false
        }
        guard !suppressNextNewLeftmostItemRelocation else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, suppressNextNewLeftmostItemRelocation armed")
            return false
        }
        guard !isApplyingProfileLayout else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, profile apply in flight")
            return false
        }
        // Prevents cascading re-applies when many apps relaunch together.
        // The launch restore bypasses it: its own chain just stamped it and there's no retry (#881).
        guard bypassMoveCooldown || !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            return false
        }
        // Not bypassable: this reads the history of unfinished applies.
        guard isAutomaticBulkApplyPermitted(caller: "applySavedLayout") else {
            return false
        }

        // Change gate, since this runs every tick. Two signals pass it:
        //
        // 1. windowIDsChanged: an item disappeared (quit or relaunch). Additions
        //    belong to relocateNewLeftmostItems; recycled window IDs aren't covered.
        // 2. layoutDiverged: a saved item is in another section. Catches drift
        //    with stable windowIDs, and cold boot for non-profile users.
        //
        // Divergence is only computed when needed, and must be seen twice (#723).
        // windowIDsChanged is trustworthy and stays immediate.
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousCycle.windowIDs)
        // Control Center Item-N windows churn IDs (Live Activities). They're never
        // saved, so ignoring them misses nothing (#736).
        let windowIDsChanged = Self.windowIDsChanged(
            previous: previousWindowIDSet.subtracting(previousCycle.ccGenericWindowIDs),
            current: currentWindowIDSet,
            previousDisplayID: previousCycle.displayID,
            currentDisplayID: currentDisplayID
        )
        let layoutDiverged: Bool
        if windowIDsChanged {
            layoutDiverged = false
        } else {
            let divergedNow = currentLayoutDivergesFromSaved(items: items, controlItems: controlItems)
            let now = ContinuousClock.now
            let decision = Self.confirmedDivergence(
                divergedNow: divergedNow,
                pendingSince: pendingDivergenceObservedAt,
                now: now
            )
            pendingDivergenceObservedAt = decision.newPendingSince
            if divergedNow, !decision.confirmed {
                MenuBarItemManager.diagLog.debug("applySavedLayout: divergence observed, awaiting confirmation on next cycle")
            } else if decision.confirmed {
                MenuBarItemManager.diagLog.debug("applySavedLayout: divergence confirmed on second consecutive cycle")
            }
            layoutDiverged = decision.confirmed
        }
        guard windowIDsChanged || layoutDiverged else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no windowID change and saved layout matches current")
            return false
        }
        // Control Center at or left of the notch is a stale position from a
        // display reconnect or widget churn. Applying against it throws the
        // Thaw icon far left; a later tick retries once it settles.
        if let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main,
           screen.hasNotch,
           let notch = screen.frameOfNotch
        {
            let rightBoundary = items.first(where: { $0.tag == .controlCenter })?.bounds.minX
                ?? screen.frame.maxX
            guard LayoutSolver.isMenuBarGeometryReady(rightBoundary: rightBoundary, notchMaxX: notch.maxX) else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, menu bar geometry not settled (rightBoundary=\(rightBoundary), notch.maxX=\(notch.maxX))"
                )
                return false
            }
        }
        // Discard the arm so it can't confirm a later, unrelated cycle.
        pendingDivergenceObservedAt = nil

        // resolvedIdentitiesOnly callers are exempt; they only touch resolved identities.
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if !resolvedIdentitiesOnly,
           Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count)
        {
            MenuBarItemManager.diagLog.info(
                "applySavedLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            return false
        }

        // A synthetic Cmd-drag would tear down an open menu. The gate stays armed.
        let menuIsOpen = await isAnyMenuBarItemMenuOpen()
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, a user move superseded the snapshot during the menu check"
            )
            return false
        }
        if menuIsOpen {
            MenuBarItemManager.diagLog.info("applySavedLayout: skipping, a menu bar item menu is open")
            return false
        }

        // Skip if no saved item is present. Base-identifier matches count only
        // when all instances share a section (Item-0:1 visible, Item-0:2 hidden doesn't).
        let sectionLookup = Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder)
        let currentIdentifiers = Set(items.map(\.uniqueIdentifier))
        let currentBaseIdentifiers = Set(items.map { Self.baseIdentifier(forSavedIdentifier: $0.uniqueIdentifier) })
        guard !Set(sectionLookup.exact.keys).isDisjoint(with: currentIdentifiers)
            || !Set(sectionLookup.unambiguousBase.keys).isDisjoint(with: currentBaseIdentifiers)
        else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no saved items currently present")
            return false
        }

        // Under resolvedIdentitiesOnly, unidentified items are left untouched;
        // the settling-end pass moves the remainder.
        var effectiveSavedOrder: [String: [String]]
        if resolvedIdentitiesOnly {
            effectiveSavedOrder = Self.savedOrderRestrictedToResolvedIdentities(
                savedSectionOrder: savedSectionOrder,
                resolvedIdentifiers: Set(
                    items.lazy.filter { $0.sourcePID != nil }.map(\.uniqueIdentifier)
                )
            )
            guard effectiveSavedOrder.values.contains(where: { !$0.isEmpty }) else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, no saved items have resolved identities yet"
                )
                return false
            }
        } else {
            effectiveSavedOrder = savedSectionOrder
        }
        let knownBaseIdentifiers = Set(items.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(items.map(\.uniqueIdentifier))
        effectiveSavedOrder = Self.savedOrderExcludingTriggerControlledIdentifiers(
            effectiveSavedOrder,
            controlledIdentifiers: triggerControlledItemIdentifiers,
            knownBaseIdentifiers: knownBaseIdentifiers,
            knownLiveIdentifiers: knownLiveIdentifiers
        )
        guard effectiveSavedOrder.values.contains(where: { !$0.isEmpty }) else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, every saved item is currently trigger-controlled"
            )
            return false
        }

        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in effectiveSavedOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }

        let trigger = if windowIDsChanged {
            "windowID change"
        } else if resolvedIdentitiesOnly {
            "layout divergence, resolved identities only"
        } else {
            "layout divergence"
        }

        // Refuse what the save path refuses. Collapsed dividers misread hidden as
        // visible, and the drags would then let the damage be saved (#868).
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: controlItems.hidden.bounds.minX,
            alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX,
            savedHiddenItemCount: effectiveSavedOrder[sectionKey(for: .hidden)]?.count ?? 0,
            // From the items passed in; no recache has run yet.
            liveHiddenItemCount: LayoutSolver.liveHiddenItemCount(
                itemBounds: items.map(\.bounds),
                hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX
            ),
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: items.map(\.bounds),
                hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            )
        )
        guard hiddenSectionHasRoom else {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); hidden section has zero width between the dividers (hidden.minX=\(controlItems.hidden.bounds.minX) windowID=\(controlItems.hidden.windowID), alwaysHidden.maxX=\(controlItems.alwaysHidden?.bounds.maxX.description ?? "nil") windowID=\(controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
            recoverStrandedHiddenDividerBeforeRefusing(
                guardSource: "applySavedLayout",
                controlItems: controlItems,
                items: items
            )
            return false
        }

        // Divider-order gate (#1027), same as the profile path.
        let dividerBounds = dividerControlItemBounds(items: items, controlItems: controlItems)
        guard LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: dividerBounds.visible,
            hiddenControlItemBounds: dividerBounds.hidden,
            alwaysHiddenControlItemBounds: dividerBounds.alwaysHidden
        ) else {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); section dividers are out of order (visibleCtrl.minX=\(dividerBounds.visible?.minX.description ?? "unresolved"), hidden.minX=\(dividerBounds.hidden.minX), alwaysHiddenCtrl.minX=\(dividerBounds.alwaysHidden?.minX.description ?? "unresolved"))"
            )
            recoverStrandedHiddenDividerBeforeRefusing(
                guardSource: "applySavedLayout",
                controlItems: controlItems,
                items: items
            )
            await recoverMisplacedVisibleControlItem(
                controlItems: controlItems,
                items: items
            )
            return false
        }

        // Display-spread gate: macOS migrates windows between displays async, and
        // moves made mid-migration strand items on the wrong screen. CG frames.
        //
        // Only items right of the hidden divider; parked items' negative x can land
        // on a display left of main. Must match the saveSectionOrder gate.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        let unparkedCenters = items
            .filter { $0.bounds.minX >= controlItems.hidden.bounds.minX }
            .map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
        if LayoutSolver.itemsSpanMultipleDisplays(itemCenters: unparkedCenters, screenFrames: screenFrames) {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); menu bar items span multiple displays (relocation in progress)"
            )
            return false
        }

        MenuBarItemManager.diagLog.info("applySavedLayout: dispatching bulk apply (\(trigger))")

        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, a user move superseded the snapshot before dispatch"
            )
            return false
        }

        // Pinning comes from existing state; savedSectionOrder has none.
        // resolvedIdentitiesOnly doubles as duringSettling: its gate-holding caller
        // can't survive Phase 0's settling wait (#943).
        guard let batchLease = beginLayoutBatch(.savedRestore) else {
            return false
        }
        defer { finishLayoutBatch(batchLease) }

        let completionGenerationBeforeApply = bulkApplyCompletionGeneration
        let restorationIdentifiersAtDispatch = triggerLayoutRestorationItemIdentifiers
        // One-shot from sortSection's no-active-profile branch: honour the
        // sorted concealed-section order this apply instead of relaxing it.
        let enforceConcealed = enforceConcealedSectionOrderOnNextSavedApply
        enforceConcealedSectionOrderOnNextSavedApply = false
        await applyProfileLayout(
            ProfileLayoutSpec(
                pinnedHidden: pinnedHiddenBundleIDs,
                pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
                sectionOrder: effectiveSavedOrder,
                itemSectionMap: itemSectionMap,
                itemOrder: effectiveSavedOrder
            ),
            source: .savedOrder,
            automatic: true,
            duringSettling: resolvedIdentitiesOnly,
            enforceConcealedSectionOrder: enforceConcealed,
            shouldBegin: {
                self.layoutBatchIsCurrent(batchLease) && (shouldBegin?() ?? true)
            }
        )
        // The completed-apply counter, not the shared one: a user drag landing in
        // between zeroes the shared counter and would clear the shields wrongly.
        if bulkApplyCompletionGeneration != completionGenerationBeforeApply,
           lastCompletedBulkApplyUnenactedMoveCount == 0
        {
            // Re-read: a gained or lost same-title sibling makes stale counts
            // clear the shield of an item the trigger still controls.
            let postApplyItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let postApplyBaseIdentifiers = Set(postApplyItems.map(\.tag.stableIdentifierBase))
            let postApplyLiveIdentifiers = Set(postApplyItems.map(\.uniqueIdentifier))
            let restored = restorationIdentifiersAtDispatch.filter { identifier in
                LayoutSolver.savedPositionByBaseID(for: identifier, in: effectiveSavedOrder) != nil
                    && !Self.isTriggerProtected(
                        identifier,
                        by: triggerControlledItemIdentifiers,
                        knownBaseIdentifiers: postApplyBaseIdentifiers,
                        knownLiveIdentifiers: postApplyLiveIdentifiers
                    )
            }
            triggerLayoutRestorationItemIdentifiers.subtract(restored)
            if !restored.isEmpty {
                MenuBarItemManager.diagLog.debug(
                    "Cleared \(restored.count) trigger release restoration shield(s) after a clean saved-layout apply"
                )
            }
        }
        return true
    }
}
