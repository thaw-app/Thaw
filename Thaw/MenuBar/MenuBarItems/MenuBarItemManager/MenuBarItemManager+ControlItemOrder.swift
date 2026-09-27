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
    /// A failed attempt still needs one cache read, since the events may have
    /// moved the item. It must not rerun the helper, or a persistent refusal
    /// becomes an endless recache/retry chain.
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

    /// Records whether a queued move passed preflight. ``MoveOptions/shouldBegin``
    /// is stored in the options struct, so it can't mutate a captured local.
    private final class MoveAttemptAcceptanceRecorder {
        var didAcceptMoveAttempt = false
        var didAcceptCurrentMove = false
    }

    /// Relocates any newly appearing items that macOS placed to the left
    /// of our control items back into the visible section.
    ///
    /// A failed attempt may still have displaced the item, so callers must
    /// recache after every accepted attempt without persisting that geometry.
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
            // Skip unresolved sourcePIDs so the placeholder "com.apple.controlcenter"
            // namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
            suppressNextNewLeftmostItemRelocation = false
            return .noAttempt
        }

        // During settling, tags can carry the placeholder namespace until sourcePID
        // resolves. Using them makes every item look new on the next pass and
        // cascades every hidden item to visible. The settling-end pass places them.
        if isInStartupSettling {
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()

            // macOS can restore our control items swapped, parking the Thaw icon
            // off screen for all of settling (~8 s), which looks like a crash (#881).
            // Safe early: it relies only on geometry and our own tag.
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

        // Lets the planner skip items already placed in a hidden section.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        // Live WindowServer reads happen here so planLeftmostMove stays pure.
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
                await reportAutomaticMoveFailure(
                    of: systemItem,
                    to: .rightOfItem(controlItems.hidden),
                    expectedSection: .visible,
                    error: error,
                    source: "the section layout"
                )
                return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
            }
            return .completed

        case let .newHideableItem(candidate, identifierToMark):
            knownItemIdentifiers.insert(identifierToMark)
            persistKnownItemIdentifiers()

            // Thaw's spacers are placed by AppKit autosave; relocating them would
            // fight it every cycle. Window ownership works while the tag is still "Item-0".
            if MenuBarSpacerManager.isSpacerTag(candidate.tag)
                || appState?.spacerManager.ownsWindowID(candidate.windowID) == true
            {
                MenuBarItemManager.diagLog.info(
                    "Skipping new-item relocation for Thaw spacer \(candidate.logString)"
                )
                // Reporting an attempt would schedule a pointless recache.
                return .noAttempt
            }

            let destination = newItemsMoveDestination(for: controlItems, among: items)

            MenuBarItemManager.diagLog.info(
                "Relocating new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
            )

            // Skip transient clone windows with no bounds.
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
                await reportAutomaticMoveFailure(
                    of: candidate,
                    to: destination,
                    expectedSection: effectiveNewItemsSection,
                    error: error,
                    source: "new-item placement"
                )
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

    /// Moves the Thaw icon back right of the hidden divider, where it is on screen.
    private func relocateThawIcon(
        _ thawIcon: MenuBarItem,
        controlItems: ControlItemPair,
        shouldBeginMove: (@MainActor () -> Bool)? = nil
    ) async -> CacheDrivenMoveOutcome {
        let beginMove = shouldBeginMove
        // With H_ctrl parked offscreen the drag strands the chevron there (#958),
        // and warping to its stale cached frame clicks whatever item sits there now.
        // Skip until the divider is back on screen.
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
            await reportAutomaticMoveFailure(
                of: thawIcon,
                to: .rightOfItem(controlItems.hidden),
                expectedSection: .visible,
                error: error,
                source: "the section layout"
            )
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        }
        return .completed
    }

    /// Relocates items whose apps quit while they were temporarily shown
    /// in the visible section back to their original section.
    ///
    /// macOS persists the temporarily-shown position, so an app that quits
    /// before rehide relaunches in visible.
    ///
    /// A failed accepted attempt can leave position-only changes the window-ID
    /// change detector can't see.
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

        // Currently shown items are handled by the normal rehide flow.
        let activelyShownTags = Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))

        let hiddenBounds = bestBounds(for: controlItems.hidden)

        // Live bounds are read here so the planner stays pure.
        var boundsForWindowID = [CGWindowID: CGRect]()
        for item in items {
            boundsForWindowID[item.windowID] = bestBounds(for: item)
        }
        let bar = PendingLedger.BarState(
            items: items,
            controlItems: controlItems,
            hiddenBounds: hiddenBounds,
            boundsForWindowID: boundsForWindowID,
            activelyShownTags: activelyShownTags
        )

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

        // Snapshot the keys: waitForRelaunch promotions mutate the dict mid-loop.
        let allTagIdentifiers = Array(pendingRelocations.keys)
        for tagIdentifier in allTagIdentifiers {
            guard let rawSectionString = pendingRelocations[tagIdentifier] else { continue }

            let entry: PendingLedger.PendingEntry
            if let sentinel = parseWaitForRelaunch(rawSectionString) {
                entry = PendingLedger.PendingEntry(
                    tagIdentifier: tagIdentifier,
                    kind: .waitForRelaunch(windowID: sentinel.windowID, section: sentinel.section, setAt: sentinel.setAt)
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
                bar: bar,
                returnInfo: PendingLedger.PendingReturnInfo(
                    destinations: pendingReturnDestinations,
                    fallbackNeighbors: fallbackNeighborByTagIdentifier
                ),
                now: Date(),
                sentinelAgeCap: MenuBarItemManager.waitForRelaunchAgeCap
            )

            // Rewrite the sentinel to its section, persist, and re-run the planner.
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
                    bar: bar,
                    returnInfo: PendingLedger.PendingReturnInfo(
                        destinations: pendingReturnDestinations,
                        fallbackNeighbors: fallbackNeighborByTagIdentifier
                    ),
                    now: Date(),
                    sentinelAgeCap: MenuBarItemManager.waitForRelaunchAgeCap
                )
            }

            switch decision {
            case let .move(item, destination):
                // The recorder outlives the loop; a stale `true` would misreport
                // this preflight rejection as a failed accepted move.
                attemptRecorder.didAcceptCurrentMove = false
                let targetSection: MenuBarSection.Name = {
                    if case let .section(section) = entry.kind {
                        return section
                    }
                    if case let .waitForRelaunch(_, section, _) = entry.kind {
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
                    await reportAutomaticMoveFailure(
                        of: item,
                        to: destination,
                        expectedSection: targetSection,
                        error: error,
                        source: "pending item restoration"
                    )
                }

            case .clearEntry:
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)

            case .promoteWaitForRelaunch:
                // Handled above. A second promote leaves the entry for next pass.
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

    private func bestBounds(for item: MenuBarItem) -> CGRect {
        item.liveBounds
    }

    /// Keeps the always-hidden control item left of the hidden one.
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

        // Moving AH_ctrl left of a parked H_ctrl drags the whole always-hidden
        // section into the parked zone. Defer to the recovery paths.
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
            await reportAutomaticMoveFailure(
                of: alwaysHidden,
                to: .leftOfItem(hidden),
                expectedSection: nil,
                error: error,
                source: "control-item ordering"
            )
            return attemptRecorder.didAcceptMoveAttempt ? .failedAttempt : .noAttempt
        }
    }

    /// Moves a visible control item that the live bar classifies outside the
    /// visible section back beside the hidden divider.
    ///
    /// Pairs with ``recoverStrandedHiddenDividerBeforeRefusing(guardSource:controlItems:items:)``
    /// so a divider-order refusal defers instead of wedging. This one undoes
    /// macOS restoring the chevron left of the hidden divider at login (#881).
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

    /// Whether any menu bar item currently has a menu open.
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
        // Cache negatives too: bulk moves call this once per move, and "no menu
        // open" is the common, expensive case.
        menuOpenCheckCachedResult = result
        menuOpenCheckCachedAt = .now
        return result
    }

    /// Updates first-seen tracking and returns whether any candidate is fresh
    /// enough, or under the pointer, to be a real open menu.
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

    /// A candidate counts as an open menu while young, or at any age while the
    /// pointer is inside it. Persistent status-level windows (Droppy's shelf,
    /// notch HUDs) would otherwise defer every move. Windows present at the
    /// first probe count as persistent; vanished IDs are pruned.
    ///
    /// A display-sized candidate is never a menu. Drop-shelf apps raise a
    /// full-screen drag-catcher during any drag, which always contains the pointer (#899).
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
    /// Half a display is far beyond any real menu; a drag-catcher overlay covers all of one.
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
