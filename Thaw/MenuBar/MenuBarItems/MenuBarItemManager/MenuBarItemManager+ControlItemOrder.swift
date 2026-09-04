//
//  MenuBarItemManager+ControlItemOrder.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Result of one cache-driven move helper.
    ///
    /// A failed attempt still needs one authoritative cache read because
    /// synthetic events may have changed position before verification failed.
    /// It must not immediately rerun the same automatic helper, however, or a
    /// persistent refusal becomes an unbounded recache/retry chain.
    enum CacheDrivenMoveOutcome: Equatable {
        case noAttempt
        case completed
        case failedAttempt

        var needsAuthoritativeRecache: Bool {
            self != .noAttempt
        }

        var shouldSuppressAutomaticMovesDuringRecache: Bool {
            self == .failedAttempt
        }

        var shouldSuppressSavedOrderPersistenceDuringRecache: Bool {
            self == .failedAttempt
        }
    }

    /// Reference box recording whether a queued move was accepted by its
    /// preflight. ``MoveOptions/shouldBegin`` escapes the call frame — it is
    /// stored in the options struct — so a captured local cannot be mutated
    /// from inside the closure.
    private final class MoveAttemptAcceptanceRecorder {
        var didAcceptMoveAttempt = false
        var didAcceptCurrentMove = false
    }

    /// Relocates any newly appearing items that macOS placed to the left
    /// of our control items back into the visible section.
    ///
    /// Returns whether no move began, a move completed, or an accepted move
    /// later failed. Even a failed attempt may have displaced the item, so
    /// callers must follow every accepted attempt with an authoritative
    /// recache without persisting that possibly partial geometry.
    func relocateNewLeftmostItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        previousWindowIDs: [CGWindowID],
        recentWindowIDs: Set<CGWindowID>,
        shouldBeginMove: (@MainActor () -> Bool)? = nil
    ) async -> CacheDrivenMoveOutcome {
        let beginMove = shouldBeginMove
        guard appState != nil else { return .noAttempt }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "relocateNewLeftmostItems: skipping for provisional AX-frame correlation"
            )
            return .noAttempt
        }

        if suppressNextNewLeftmostItemRelocation {
            // Seed known identifiers so these baseline items won't be treated as "new"
            // on subsequent cache passes, then clear the suppression flag.
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
            suppressNextNewLeftmostItemRelocation = false
            return .noAttempt
        }

        // During startup settling, the first cache pass may have items tagged
        // with wrong namespaces (e.g. com.apple.controlcenter when sourcePID
        // hasn't resolved yet). Using those wrong tags to build hiddenTags /
        // alwaysHiddenTags causes ALL items to appear as "new" on the next
        // pass with correct sourcePIDs, triggering a destructive relocation
        // cascade that moves every hidden/always-hidden item to visible.
        // Seed identifiers and skip relocation; the settling-end restore pass
        // will handle correct placement.
        if isInStartupSettling {
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()

            // The Thaw icon is exempt from the deferral above. macOS can
            // restore our two control items in the wrong relative order,
            // parking the visible one left of the hidden divider — i.e.
            // off screen. Waiting for the settling-end pass to correct that
            // leaves the menu bar with no Thaw icon for as long as settling
            // runs, which is ~8 s when Control Center is slow to hand out
            // source PIDs, and reads as the app having crashed (#881).
            //
            // Safe to act on early because it turns only on geometry and our
            // own control item's tag; it is the namespace tags of *other*
            // items that aren't trustworthy yet.
            if let thawIcon = LayoutSolver.planThawIconMove(
                items: items,
                hiddenBounds: bestBounds(for: controlItems.hidden)
            ) {
                return await relocateThawIcon(
                    thawIcon,
                    controlItems: controlItems,
                    shouldBeginMove: shouldBeginMove
                )
            }
            return .noAttempt
        }

        // Cached hidden / always-hidden tags from the prior cache cycle.
        // The planner uses these to short-circuit re-relocating items
        // already placed in a hidden section.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        // Pre-compute live state for the planner. hiddenBounds and the
        // section classification both require the live Window Server;
        // computing them here keeps planLeftmostMove pure over its inputs.
        let hiddenBounds = bestBounds(for: controlItems.hidden)
        var sectionContext = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        var sectionByWindowID = [CGWindowID: MenuBarSection.Name]()
        for item in items {
            if let section = sectionContext.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

        let decision = LayoutSolver.planLeftmostMove(
            items: items,
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: sectionByWindowID,
                previousWindowIDs: previousWindowIDs,
                recentWindowIDs: recentWindowIDs
            ),
            savedSectionOrder: savedSectionOrder,
            knownItemIdentifiers: knownItemIdentifiers,
            hiddenTags: hiddenTags,
            alwaysHiddenTags: alwaysHiddenTags,
            effectiveNewItemsSection: effectiveNewItemsSection
        )

        switch decision {
        case let .thawIcon(thawIcon):
            return await relocateThawIcon(
                thawIcon,
                controlItems: controlItems,
                shouldBeginMove: shouldBeginMove
            )

        case let .systemItem(systemItem):
            MenuBarItemManager.diagLog.info("Relocating non-hideable system item \(systemItem.logString) to visible section")
            let attemptRecorder = MoveAttemptAcceptanceRecorder()
            do {
                try await move(
                    item: systemItem,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true,
                    options: .init(shouldBegin: {
                        let shouldBegin = beginMove?() ?? true
                        if shouldBegin {
                            attemptRecorder.didAcceptMoveAttempt = true
                        }
                        return shouldBegin
                    })
                )
            } catch EventError.moveSuperseded {
                MenuBarItemManager.diagLog.debug(
                    "Skipping stale system-item relocation for \(systemItem.logString)"
                )
                return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate system item \(systemItem.logString): \(error)")
                return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
            }
            return .completed

        case let .newHideableItem(candidate, identifierToMark):
            // Track this item so future cache cycles don't treat it as new.
            knownItemIdentifiers.insert(identifierToMark)
            persistKnownItemIdentifiers()

            // Thaw's own spacers are placed by AppKit's autosave (seeded next
            // to the Thaw icon) — relocating them like new third-party items
            // would fight that position every cycle. Window ownership is the
            // reliable check right after creation, when the cached tag can
            // still be a generic "Item-0".
            if MenuBarSpacerManager.isSpacerTag(candidate.tag)
                || appState?.spacerManager.ownsWindowID(candidate.windowID) == true
            {
                MenuBarItemManager.diagLog.info(
                    "Skipping new-item relocation for Thaw spacer \(candidate.logString)"
                )
                // Nothing was relocated: reporting an attempt would make the
                // caller treat this cycle as interrupted and schedule an extra
                // recache for a no-op. The spacer is already marked known.
                return .noAttempt
            }

            let destination = newItemsMoveDestination(for: controlItems, among: items)

            MenuBarItemManager.diagLog.info(
                "Relocating new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
            )

            // Skip items with no valid bounds (transient clone windows
            // etc.). This live check stays in the orchestrator because
            // it requires Bridging.
            guard Bridging.getWindowBounds(for: candidate.windowID) != nil else {
                MenuBarItemManager.diagLog.warning("Skipping relocation for \(candidate.logString); no valid bounds, likely transient")
                return .noAttempt
            }

            let attemptRecorder = MoveAttemptAcceptanceRecorder()
            do {
                try await move(
                    item: candidate,
                    to: destination,
                    skipInputPause: true,
                    options: .init(shouldBegin: {
                        let shouldBegin = beginMove?() ?? true
                        if shouldBegin {
                            attemptRecorder.didAcceptMoveAttempt = true
                        }
                        return shouldBegin
                    })
                )
            } catch EventError.moveSuperseded {
                MenuBarItemManager.diagLog.debug(
                    "Skipping stale new-item relocation for \(candidate.logString)"
                )
                return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate \(candidate.logString): \(error)")
                return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
            }
            return .completed

        case let .noop(reason):
            switch reason {
            case .unresolvedSourcePID:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: skipping, hideable items have unresolved sourcePIDs"
                )
            case .alreadyInTarget:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: candidate already in \(effectiveNewItemsSection.logString), skipping"
                )
            case .noNewCandidate, .noLeftmostItems:
                break
            }
            return .noAttempt
        }
    }

    /// Moves the Thaw icon back to the right of the hidden divider, where it
    /// is on screen. Shared by the startup-settling path and the regular
    /// planner path, which reach the same decision from different inputs.
    private func relocateThawIcon(
        _ thawIcon: MenuBarItem,
        controlItems: ControlItemPair,
        shouldBeginMove: (@MainActor () -> Bool)? = nil
    ) async -> CacheDrivenMoveOutcome {
        let beginMove = shouldBeginMove
        // The destination is the right of H_ctrl. When the divider itself is
        // parked offscreen, that destination is in the parked zone: the drag
        // strands the chevron beside it, invisible to the user (#958's
        // 16:32:49.505 move dragged the chevron toward a divider parked at
        // minX -3440). Worse, the move engine warps to the chevron's cached
        // frame to start the drag, and a cached on-screen frame over a
        // physically parked chevron clicks whatever item now occupies that
        // frame. The #881 recovery this relocation exists for needs the
        // divider on screen anyway; until it is, skipping is strictly better.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        if !LayoutSolver.isOnScreen(bounds: bestBounds(for: controlItems.hidden), screenFrames: screenFrames) {
            MenuBarItemManager.diagLog.warning(
                "Skipping Thaw icon relocation, the hidden divider is parked offscreen (minX=\(controlItems.hidden.bounds.minX)); moving the icon beside it would strand both"
            )
            return .noAttempt
        }
        MenuBarItemManager.diagLog.info("Relocating Thaw icon \(thawIcon.logString) to visible section")
        let attemptRecorder = MoveAttemptAcceptanceRecorder()
        do {
            try await move(
                item: thawIcon,
                to: .rightOfItem(controlItems.hidden),
                skipInputPause: true,
                options: .init(shouldBegin: {
                    let shouldBegin = beginMove?() ?? true
                    if shouldBegin {
                        attemptRecorder.didAcceptMoveAttempt = true
                    }
                    return shouldBegin
                })
            )
        } catch EventError.moveSuperseded {
            MenuBarItemManager.diagLog.debug(
                "Skipping stale Thaw-icon relocation for \(thawIcon.logString)"
            )
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        } catch {
            MenuBarItemManager.diagLog.error("Failed to relocate Thaw icon \(thawIcon.logString): \(error)")
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        }
        return .completed
    }

    /// Relocates items whose apps quit while they were temporarily shown
    /// in the visible section back to their original section.
    ///
    /// When `temporarilyShow` moves an item to the visible section, macOS
    /// persists that position. If the app quits before rehide can move it
    /// back, the icon will reappear in the visible section on relaunch.
    /// This method checks for such items and moves them back.
    ///
    /// Returns whether no move began, a move completed, or an accepted move
    /// later failed. A failed accepted attempt can still leave position-only
    /// geometry that the normal window-ID change detector cannot observe.
    func relocatePendingItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        shouldBeginMove: (@MainActor () -> Bool)? = nil
    ) async -> CacheDrivenMoveOutcome {
        let beginMove = shouldBeginMove
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "relocatePendingItems: skipping for provisional AX-frame correlation"
            )
            return .noAttempt
        }

        guard !pendingRelocations.isEmpty else {
            return .noAttempt
        }

        // Don't interfere with items that are currently temporarily shown ;
        // those are handled by the normal rehide flow.
        let activelyShownTags = Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))

        let hiddenBounds = bestBounds(for: controlItems.hidden)

        // Pre-compute live per-item bounds for the planner's "already in
        // hidden section" comparison. Done here so the planner stays pure
        // over its inputs (no Bridging calls inside).
        var boundsForWindowID = [CGWindowID: CGRect]()
        for item in items {
            boundsForWindowID[item.windowID] = bestBounds(for: item)
        }

        // Extract fallback neighbor tags from temporarilyShownItemContexts.
        // The planner only needs the tag-identifier → neighbor mapping;
        // exposing the full context type to the planner would tangle its
        // signature with private state.
        var fallbackNeighborByTagIdentifier = [String: MenuBarItemTag]()
        for context in temporarilyShownItemContexts {
            if let neighbor = context.fallbackNeighbor?.tag {
                fallbackNeighborByTagIdentifier[context.tag.tagIdentifier] = neighbor
            }
        }

        let attemptRecorder = MoveAttemptAcceptanceRecorder()
        var didCompleteMove = false
        var didFailAcceptedMove = false
        func outcome() -> CacheDrivenMoveOutcome {
            if didFailAcceptedMove {
                return .failedAttempt
            }
            if didCompleteMove {
                return .completed
            }
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        }

        // Iterate a snapshot of the dict keys so promotions of waitForRelaunch
        // sentinels mid-loop don't disturb iteration. The planner is called
        // per entry; the orchestrator handles persistence and re-runs after
        // a promotion so the regular section path executes.
        let allTagIdentifiers = Array(pendingRelocations.keys)
        for tagIdentifier in allTagIdentifiers {
            guard let rawSectionString = pendingRelocations[tagIdentifier] else { continue }

            // Parse the raw string into a typed PendingEntry for the planner.
            let entry: PendingLedger.PendingEntry
            if let sentinel = parseWaitForRelaunch(rawSectionString) {
                entry = PendingLedger.PendingEntry(
                    tagIdentifier: tagIdentifier,
                    kind: .waitForRelaunch(windowID: sentinel.windowID, section: sentinel.section)
                )
            } else if let parsedSection = sectionName(for: rawSectionString) {
                entry = PendingLedger.PendingEntry(tagIdentifier: tagIdentifier, kind: .section(parsedSection))
            } else {
                // Malformed entry; drop it.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                continue
            }

            var decision = PendingLedger.planPendingMove(
                entry: entry,
                items: items,
                controlItems: controlItems,
                hiddenBounds: hiddenBounds,
                boundsForWindowID: boundsForWindowID,
                activelyShownTags: activelyShownTags,
                returnInfo: PendingLedger.PendingReturnInfo(
                    destinations: pendingReturnDestinations,
                    fallbackNeighbors: fallbackNeighborByTagIdentifier
                )
            )

            // Handle a sentinel promotion in-place: rewrite pendingRelocations
            // to the regular section key, persist, then re-run the planner
            // for the same entry so the regular section path executes.
            if case let .promoteWaitForRelaunch(promotedSection) = decision {
                if let item = items.first(where: { entry.tagIdentifier == $0.tag.tagIdentifier }) {
                    MenuBarItemManager.diagLog.info(
                        "relocatePendingItems: \(item.logString) has new windowID; clearing waitForRelaunch sentinel"
                    )
                }
                pendingRelocations[tagIdentifier] = sectionKey(for: promotedSection)
                persistPendingRelocations()

                let promotedEntry = PendingLedger.PendingEntry(tagIdentifier: tagIdentifier, kind: .section(promotedSection))
                decision = PendingLedger.planPendingMove(
                    entry: promotedEntry,
                    items: items,
                    controlItems: controlItems,
                    hiddenBounds: hiddenBounds,
                    boundsForWindowID: boundsForWindowID,
                    activelyShownTags: activelyShownTags,
                    returnInfo: PendingLedger.PendingReturnInfo(
                        destinations: pendingReturnDestinations,
                        fallbackNeighbors: fallbackNeighborByTagIdentifier
                    )
                )
            }

            switch decision {
            case let .move(item, destination):
                var didAcceptCurrentMove = false
                let targetSection: MenuBarSection.Name = {
                    if case let .section(section) = entry.kind {
                        return section
                    }
                    if case let .waitForRelaunch(_, section) = entry.kind {
                        return section
                    }
                    return .hidden
                }()
                MenuBarItemManager.diagLog.info(
                    """
                    Relocating \(item.logString) back to \
                    \(targetSection.logString) after app relaunch
                    """
                )
                do {
                    try await move(
                        item: item,
                        to: destination,
                        skipInputPause: true,
                        options: .init(shouldBegin: {
                            let shouldBegin = beginMove?() ?? true
                            if shouldBegin {
                                attemptRecorder.didAcceptMoveAttempt = true
                                attemptRecorder.didAcceptCurrentMove = true
                            }
                            return shouldBegin
                        })
                    )
                    pendingRelocations.removeValue(forKey: tagIdentifier)
                    pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                    didCompleteMove = true
                } catch EventError.moveSuperseded {
                    didFailAcceptedMove = didFailAcceptedMove || attemptRecorder.didAcceptCurrentMove
                    MenuBarItemManager.diagLog.debug(
                        "Stopping stale pending-item relocations before moving \(item.logString)"
                    )
                    persistPendingRelocations()
                    return outcome()
                } catch {
                    didFailAcceptedMove = didFailAcceptedMove || attemptRecorder.didAcceptCurrentMove
                    MenuBarItemManager.diagLog.error(
                        """
                        Failed to relocate \(item.logString) back to \
                        \(targetSection.logString): \(error)
                        """
                    )
                }

            case .clearEntry:
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)

            case .promoteWaitForRelaunch:
                // Unreachable: handled above by re-running the planner with
                // the promoted entry. If the planner returns promote a
                // second time we just leave the entry alone for next pass.
                break

            case let .skip(reason):
                switch reason {
                case .waitForRelaunchActive:
                    if let item = items.first(where: { entry.tagIdentifier == $0.tag.tagIdentifier }) {
                        MenuBarItemManager.diagLog.debug(
                            "relocatePendingItems: skipping \(item.logString); waitForRelaunch sentinel active (same windowID)"
                        )
                    }
                case .activelyShown, .itemNotPresent:
                    break
                }
            }
        }

        persistPendingRelocations()
        return outcome()
    }

    /// Returns the best-known bounds for a menu bar item.
    private func bestBounds(for item: MenuBarItem) -> CGRect {
        item.liveBounds
    }

    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    func enforceControlItemOrder(
        controlItems: ControlItemPair,
        shouldBeginMove: (@MainActor () -> Bool)? = nil
    ) async -> CacheDrivenMoveOutcome {
        let beginMove = shouldBeginMove
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "Skipping control item order enforcement for provisional AX-frame correlation"
            )
            return .noAttempt
        }

        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            bestBounds(for: hidden).maxX <= bestBounds(for: alwaysHidden).minX
        else {
            return .noAttempt
        }

        // Moving AH_ctrl to the left of a parked H_ctrl drops the entire
        // always-hidden section into the parked zone with it. The inversion
        // this enforces cannot be fixed while the reference divider is
        // stranded; defer to the recovery paths the same way the boundary
        // repair and the per-item moves do.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        if !LayoutSolver.isOnScreen(bounds: bestBounds(for: hidden), screenFrames: screenFrames) {
            MenuBarItemManager.diagLog.warning(
                "Skipping control item order enforcement, the hidden divider is parked offscreen (minX=\(hidden.bounds.minX))"
            )
            return .noAttempt
        }

        let attemptRecorder = MoveAttemptAcceptanceRecorder()
        do {
            MenuBarItemManager.diagLog.debug("Control items have incorrect order")
            try await move(
                item: alwaysHidden,
                to: .leftOfItem(hidden),
                skipInputPause: true,
                options: .init(shouldBegin: {
                    let shouldBegin = beginMove?() ?? true
                    if shouldBegin {
                        attemptRecorder.didAcceptMoveAttempt = true
                    }
                    return shouldBegin
                })
            )
            return .completed
        } catch EventError.moveSuperseded {
            MenuBarItemManager.diagLog.debug("Skipping stale control-item order enforcement")
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        } catch {
            MenuBarItemManager.diagLog.error("Error enforcing control item order: \(error)")
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        }
    }

    /// Moves a visible control item that the live bar classifies outside the
    /// visible section back beside the hidden divider.
    ///
    /// Pairs with ``recoverStrandedHiddenDividerBeforeRefusing(guardSource:controlItems:items:)``
    /// on the divider-order refusal: that one un-parks the hidden divider,
    /// this one undoes the #881 login-restoration shape where macOS returns
    /// the chevron left of the hidden divider. Together they give a refused
    /// apply a path back to the ordering its gate requires, so the refusal
    /// defers rather than wedges. No-op when the chevron already sits right
    /// of the hidden divider — which is also most refusals, because
    /// repositioning the dividers is what re-classifies it.
    func recoverMisplacedVisibleControlItem(
        controlItems: ControlItemPair,
        items: [MenuBarItem]
    ) async {
        guard appState?.isDraggingMenuBarItem != true else { return }
        guard let misplaced = LayoutSolver.planThawIconMove(
            items: items,
            hiddenBounds: bestBounds(for: controlItems.hidden)
        ) else { return }
        _ = await relocateThawIcon(misplaced, controlItems: controlItems)
    }

    /// Returns a Boolean value that indicates whether any menu bar item
    /// currently has a menu open.
    func isAnyMenuBarItemMenuOpen() async -> Bool {
        let cacheFreshness: Duration = .milliseconds(250)

        if let cachedAt = menuOpenCheckCachedAt,
           cachedAt.duration(to: .now) <= cacheFreshness,
           let cachedResult = menuOpenCheckCachedResult
        {
            MenuBarItemManager.diagLog.debug("Menu open check: using cached result \(cachedResult)")
            return cachedResult
        }

        if let existingTask = menuOpenCheckTask {
            MenuBarItemManager.diagLog.debug("Menu open check: joining in-flight probe")
            return await applyMenuWindowPersistenceFilter(to: existingTask.value)
        }

        let cachedItems = itemCache.managedItems.filter(\.isOnScreen)
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description

        let task = Task.detached(priority: .utility) { () -> [MenuWindowCandidate] in
            // Get all on-screen windows.
            let windows = WindowInfo.createWindows(option: .onScreen)
            let potentialMenuWindows = windows.filter { window in
                guard window.isMenuRelated, window.title?.isEmpty ?? true else {
                    return false
                }
                guard window.owningApplication?.bundleIdentifier != controlCenterBundleID else {
                    MenuBarItemManager.diagLog.debug(
                        "Skipping Control Center window: PID \(window.ownerPID), title: \(window.title ?? "nil")"
                    )
                    return false
                }
                return true
            }

            guard !potentialMenuWindows.isEmpty else {
                MenuBarItemManager.diagLog.debug(
                    "Menu open check: no candidate menu windows on screen"
                )
                return []
            }

            let fastPathPIDs = Set(cachedItems.compactMap { item -> pid_t? in
                if let sourcePID = item.sourcePID {
                    return sourcePID
                }
                guard item.owningApplication?.bundleIdentifier != controlCenterBundleID else {
                    return nil
                }
                return item.ownerPID
            })

            MenuBarItemManager.diagLog.debug(
                """
                Checking for open menus - fast path with \(cachedItems.count) cached menu bar items, \
                \(fastPathPIDs.count) candidate PIDs, \(potentialMenuWindows.count) candidate menu windows
                """
            )

            let fastPathMatches = potentialMenuWindows.filter { window in
                let isMenuOpen = fastPathPIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on fast path: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated), bounds: \(NSStringFromRect(window.bounds))
                        """
                    )
                }
                return isMenuOpen
            }

            if !fastPathMatches.isEmpty {
                MenuBarItemManager.diagLog.debug("Menu open check: \(fastPathMatches.count) candidate windows (fast path)")
                return fastPathMatches.map { MenuWindowCandidate(windowID: $0.windowID, bounds: $0.bounds) }
            }

            let unresolvedWindows = WindowInfo.createWindows(
                from: cachedItems.compactMap { item in
                    guard item.sourcePID == nil, !item.isControlItem else {
                        return nil
                    }
                    guard item.owningApplication?.bundleIdentifier == controlCenterBundleID else {
                        return nil
                    }
                    return item.windowID
                }
            )

            guard !unresolvedWindows.isEmpty else {
                MenuBarItemManager.diagLog.debug("Menu open check: no candidate windows (fast path)")
                return []
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check: precise fallback resolving \(unresolvedWindows.count) unresolved window source PIDs"
            )

            let resolvedPIDs = await MenuBarItemManager.resolveAllSourcePIDs(for: unresolvedWindows)

            let precisePIDs = fastPathPIDs.union(resolvedPIDs)
            let preciseMatches = potentialMenuWindows.filter { window in
                let isMenuOpen = precisePIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on precise fallback: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated), bounds: \(NSStringFromRect(window.bounds))
                        """
                    )
                }
                return isMenuOpen
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check: \(preciseMatches.count) candidate windows (precise fallback with \(resolvedPIDs.count) resolved PIDs)"
            )
            return preciseMatches.map { MenuWindowCandidate(windowID: $0.windowID, bounds: $0.bounds) }
        }

        menuOpenCheckTask = task
        let matchedWindowIDs = await task.value
        menuOpenCheckTask = nil
        let result = applyMenuWindowPersistenceFilter(to: matchedWindowIDs)
        // Cache negative results too: bulk move operations (applyProfileLayout)
        // call this guard once per move, and re-enumerating on-screen windows
        // for every move when no menu is open is the common, expensive case.
        // Both polarities share the same freshness window.
        menuOpenCheckCachedResult = result
        menuOpenCheckCachedAt = .now
        return result
    }

    /// Updates first-seen tracking for the matched candidate windows and
    /// returns whether any of them is fresh enough — or currently under the
    /// pointer — to be a real open menu.
    private func applyMenuWindowPersistenceFilter(to candidates: [MenuWindowCandidate]) -> Bool {
        let outcome = MenuBarItemManager.classifyMenuWindowCandidates(
            candidates: candidates,
            pointerLocation: CGEvent(source: nil)?.location,
            firstSeen: menuWindowFirstSeen,
            now: .now,
            isFirstProbe: !hasSeededMenuWindowProbe,
            threshold: MenuBarItemManager.menuWindowPersistenceThreshold,
            displayBounds: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        )
        menuWindowFirstSeen = outcome.updatedFirstSeen
        hasSeededMenuWindowProbe = true
        if !outcome.ignoredPersistentWindowIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "Menu open check: ignoring \(outcome.ignoredPersistentWindowIDs.count) persistent candidate window(s) \(outcome.ignoredPersistentWindowIDs.sorted())"
            )
        }
        MenuBarItemManager.diagLog.debug("Menu open check result: \(outcome.isMenuOpen)")
        return outcome.isMenuOpen
    }

    /// Pure classification core for the open-menu probe: a candidate window
    /// counts as an open menu while it is young, or at any age while the
    /// pointer is inside it (a user interacting with a long-open menu, or
    /// mid-drop on a shelf). Real menus are transient; persistent
    /// status-level windows (Droppy's shelf, notch HUDs) stay on screen for
    /// the app's whole lifetime and previously deferred every move
    /// indefinitely. Windows already on screen at the first probe are
    /// grandfathered as persistent, and entries for windows that
    /// disappeared are pruned so a reused window ID starts fresh.
    ///
    /// A display-sized candidate is never a menu, whatever its age and
    /// wherever the pointer is. Drop-shelf utilities raise an invisible
    /// menu-level drag-catcher over the whole screen during any drag
    /// session — including the user's own drag inside the layout bar — and
    /// a window that spans the display contains the pointer wherever it
    /// goes, so the under-pointer rule held the probe open for as long as
    /// the overlay stayed up and every drag the user made deferred itself
    /// (#899's greyed-out layout bar).
    static nonisolated func classifyMenuWindowCandidates(
        candidates: [MenuWindowCandidate],
        pointerLocation: CGPoint?,
        firstSeen: [CGWindowID: ContinuousClock.Instant],
        now: ContinuousClock.Instant,
        isFirstProbe: Bool,
        threshold: Duration,
        displayBounds: [CGRect] = []
    ) -> (
        isMenuOpen: Bool,
        updatedFirstSeen: [CGWindowID: ContinuousClock.Instant],
        ignoredPersistentWindowIDs: Set<CGWindowID>
    ) {
        let matchedWindowIDs = Set(candidates.map(\.windowID))
        var updatedFirstSeen = firstSeen.filter { matchedWindowIDs.contains($0.key) }
        let firstSeenForNewWindows = isFirstProbe ? now - threshold : now
        var isMenuOpen = false
        var ignored = Set<CGWindowID>()
        for candidate in candidates {
            let firstSeenAt: ContinuousClock.Instant
            if let existing = updatedFirstSeen[candidate.windowID] {
                firstSeenAt = existing
            } else {
                firstSeenAt = firstSeenForNewWindows
                updatedFirstSeen[candidate.windowID] = firstSeenAt
            }
            guard !Self.isDisplaySizedWindow(candidate.bounds, displayBounds: displayBounds) else {
                ignored.insert(candidate.windowID)
                continue
            }
            let isYoung = firstSeenAt.duration(to: now) < threshold
            let isUnderPointer = pointerLocation.map(candidate.bounds.contains) ?? false
            if isYoung || isUnderPointer {
                isMenuOpen = true
            } else {
                ignored.insert(candidate.windowID)
            }
        }
        return (isMenuOpen, updatedFirstSeen, ignored)
    }

    /// Whether a window covers enough of a display it touches to be an
    /// overlay rather than a menu.
    ///
    /// Half a display is far beyond any real menu — even a Wi-Fi picker
    /// with a long network list stays a narrow column — while a
    /// drag-catcher overlay covers all of one.
    static nonisolated func isDisplaySizedWindow(_ bounds: CGRect, displayBounds: [CGRect]) -> Bool {
        guard !bounds.isEmpty else {
            return false
        }
        return displayBounds.contains { display in
            !display.isEmpty
                && display.intersects(bounds)
                && bounds.width * bounds.height >= display.width * display.height * 0.5
        }
    }

    private static nonisolated func resolveAllSourcePIDs(for windows: [WindowInfo]) async -> Set<pid_t> {
        let pids = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows)
        return Set(pids.compacted())
    }
}
