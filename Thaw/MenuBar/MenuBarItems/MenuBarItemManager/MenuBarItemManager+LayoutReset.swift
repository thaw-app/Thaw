//
//  MenuBarItemManager+LayoutReset.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: Layout Reset

extension MenuBarItemManager {
    enum LayoutResetError: LocalizedError {
        case missingAppState
        case missingControlItems
        case alreadyInProgress

        var errorDescription: String? {
            switch self {
            case .missingAppState:
                "Unable to access app state"
            case .missingControlItems:
                "Couldn't find section dividers in the menu bar"
            case .alreadyInProgress:
                "A layout reset is already in progress"
            }
        }

        var recoverySuggestion: String? {
            "Make sure \(Constants.displayName) is running and try again."
        }
    }

    /// Resets layout data to a fresh-install state and moves every movable,
    /// hideable item except the Thaw icon to Hidden.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToFreshState() async throws -> Int {
        try await resetLayout(to: .hidden)
    }

    /// Moves every movable, hideable item except the Thaw icon to Visible.
    func resetLayoutToVisible() async throws -> Int {
        try await resetLayout(to: .visible)
    }

    /// Moves every movable, hideable item except the Thaw icon to Always Hidden.
    func resetLayoutToAlwaysHidden() async throws -> Int {
        try await resetLayout(to: .alwaysHidden)
    }

    private func resetLayout(to target: LayoutResetTarget) async throws -> Int {
        guard !isResettingLayout else {
            MenuBarItemManager.diagLog.warning("resetLayout: already in progress, rejecting concurrent reset")
            throw LayoutResetError.alreadyInProgress
        }

        MenuBarItemManager.diagLog.info("Resetting menu bar layout to \(target.logString)")
        // A user reset is authoritative; settling would block the post-reset restore and save.
        startupSettlingTask?.cancel()
        isInStartupSettling = false
        settlingDeadline = nil
        settlingExpectedBundleIDs.removeAll()
        settlingKind = nil
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWID
        ) else {
            MenuBarItemManager.diagLog.error("Layout reset aborted: missing hidden section control item")

            // Nudge macOS to recreate the control items, then retry once.
            if appState.settings.advanced.enableAlwaysHiddenSection {
                appState.settings.advanced.enableAlwaysHiddenSection = false
                try? await Task.sleep(for: .milliseconds(50))
                appState.settings.advanced.enableAlwaysHiddenSection = true
                try? await Task.sleep(for: .milliseconds(150))

                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                if let retryControlItems = ControlItemPair(
                    items: &items,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ), retryControlItems.canRepositionControlItems {
                    guard !target.requiresAlwaysHiddenDivider || retryControlItems.alwaysHidden != nil else {
                        throw LayoutResetError.missingControlItems
                    }
                    MenuBarItemManager.diagLog.info("Recovered hidden section control item after re-enabling always-hidden section")
                    prepareLayoutStateForReset()
                    _ = await enforceControlItemOrder(controlItems: retryControlItems)
                    return try await resetLayoutWithControlItems(
                        controlItems: retryControlItems,
                        items: items,
                        target: target
                    )
                }
            }

            throw LayoutResetError.missingControlItems
        }

        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted: control items resolved only by provisional AX-frame correlation"
            )
            throw LayoutResetError.missingControlItems
        }
        guard !target.requiresAlwaysHiddenDivider || controlItems.alwaysHidden != nil else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted: always-hidden section divider is unavailable"
            )
            throw LayoutResetError.missingControlItems
        }

        // A provisional divider lookup must leave the saved layout intact.
        prepareLayoutStateForReset()

        _ = await enforceControlItemOrder(controlItems: controlItems)

        return try await resetLayoutWithControlItems(
            controlItems: controlItems,
            items: items,
            target: target
        )
    }

    private func prepareLayoutStateForReset() {
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        ControlItemDefaults.resetChevronPositions()

        knownItemIdentifiers.removeAll()
        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        pendingRelocations.removeAll()
        pendingReturnDestinations.removeAll()
        savedSectionOrder.removeAll()
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        persistKnownItemIdentifiers()
        persistPinnedBundleIDs()
        persistPendingRelocations()
        persistSavedSectionOrder()
        // Old retirements would keep pruning identifiers from the rebuilt layout.
        staleIdentifierLedger.removeAll()
        temporarilyShownItemContexts.removeAll()

        newItemsPlacement = NewItemsPlacement.defaultValue
        Defaults.removeObject(forKey: .newItemsSection)
        Defaults.removeObject(forKey: .newItemsPlacementData)
        suppressNextNewLeftmostItemRelocation = true
    }

    private func resetLayoutWithControlItems(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        target: LayoutResetTarget
    ) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.menuBarManager.iceBarPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        func destination(for controls: ControlItemPair) -> MoveDestination? {
            switch target {
            case .visible:
                .rightOfItem(controls.hidden)
            case .hidden:
                .leftOfItem(controls.hidden)
            case .alwaysHidden:
                controls.alwaysHidden.map(MoveDestination.leftOfItem)
            }
        }

        func itemsOutsideTarget(_ items: [MenuBarItem], controls: ControlItemPair) -> [MenuBarItem] {
            let hiddenBounds = Bridging.getWindowBounds(for: controls.hidden.windowID)
                ?? controls.hidden.bounds
            let alwaysHiddenBounds = controls.alwaysHidden.flatMap {
                Bridging.getWindowBounds(for: $0.windowID) ?? $0.bounds
            }
            return items.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let itemBounds = item.liveBounds
                return !target.contains(
                    itemBounds: itemBounds,
                    hiddenBounds: hiddenBounds,
                    alwaysHiddenBounds: alwaysHiddenBounds
                )
            }
        }

        func movePass(_ items: [MenuBarItem], controls: ControlItemPair) async -> Int {
            guard let destination = destination(for: controls) else {
                return items.count
            }
            var failed = 0
            for item in items {
                if item.tag == .visibleControlItem {
                    continue // Keep the Thaw icon in the visible section if enabled.
                }

                guard item.isMovable, item.canBeHidden, !item.isControlItem else {
                    continue
                }

                do {
                    try await move(
                        item: item,
                        to: destination,
                        skipInputPause: true,
                        options: .init(watchdogTimeout: Self.layoutWatchdogTimeout)
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during layout reset: \(error)")
                }
            }
            return failed
        }

        let firstPassItems = target.movesAllCandidatesInFirstPass
            ? items
            : itemsOutsideTarget(items, controls: controlItems)
        _ = await movePass(firstPassItems, controls: controlItems)

        try? await Task.sleep(for: .milliseconds(200))

        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedMoves = 0
        let refreshHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let refreshAlwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        guard let refreshedControls = ControlItemPair(
            items: &refreshedItems,
            hiddenControlItemWindowID: refreshHiddenWID,
            alwaysHiddenControlItemWindowID: refreshAlwaysHiddenWID
        ), refreshedControls.canRepositionControlItems,
        !target.requiresAlwaysHiddenDivider || refreshedControls.alwaysHidden != nil
        else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted before pass 2: authoritative section dividers are unavailable"
            )
            throw LayoutResetError.missingControlItems
        }

        let notYetInTarget = itemsOutsideTarget(refreshedItems, controls: refreshedControls)
        if !notYetInTarget.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "Layout reset pass 2: \(notYetInTarget.count) items not yet in \(target.logString)"
            )
            failedMoves = await movePass(notYetInTarget, controls: refreshedControls)
        }

        cacheActor.clearCachedItemWindowIDs()
        itemCache = ItemCache(displayID: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let token = self.addBackgroundCacheWaiter(continuation)
            Task { [weak self] in
                await self?.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true), waiterToken: token)
            }
            // Watchdog: the cache call can bail before the gate or its nested recache
            // may never run. Whoever removes the token first resumes.
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.layoutWatchdogTimeout)
                guard let self, self.backgroundCacheWaiters[token] != nil else { return }
                MenuBarItemManager.diagLog.warning(
                    "resetLayout: background cache wait timed out after \(MenuBarItemManager.layoutWatchdogTimeout); resuming via watchdog"
                )
                self.resumeBackgroundCacheWaiter(token)
            }
        }
        suppressNextNewLeftmostItemRelocation = false

        await MainActor.run {
            appState.imageCache.clearAll()
            appState.imageCache.performCacheCleanup()
        }

        if itemCache.displayID != nil {
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }

        // Clears a -1 sentinel cached while the menu bar window was unavailable mid-reset.
        NSScreen.invalidateMenuBarHeightCache()

        return failedMoves
    }

    /// On termination, moves items stuck at x=-1 back to visible, or Control
    /// Center's preferences keep them stuck. Normally hidden items are left alone.
    ///
    /// - Returns: The number of items that failed to move.
    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        MenuBarItemManager.diagLog.info("Checking for blocked items (x=-1) to restore before app termination")

        guard let appState else {
            MenuBarItemManager.diagLog.error("Cannot restore items: missing appState")
            return 0
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        let blockedItems = items.filter { item in
            guard item.isMovable, !item.isControlItem else { return false }
            let bounds = item.liveBounds
            return bounds.origin.x == -1
        }

        guard !blockedItems.isEmpty else {
            MenuBarItemManager.diagLog.debug("No blocked items found - skipping restoration")
            return 0
        }

        MenuBarItemManager.diagLog.warning("Found \(blockedItems.count) blocked items at x=-1, attempting to restore")

        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWID
        ), controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.error("Cannot restore items: unable to find hidden control item")
            return blockedItems.count
        }

        var failedMoves = 0

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        for item in blockedItems {
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true,
                    options: .init(watchdogTimeout: Self.layoutWatchdogTimeout)
                )
                MenuBarItemManager.diagLog.info("Successfully restored blocked item \(item.logString) to visible section")
            } catch {
                failedMoves += 1
                MenuBarItemManager.diagLog.error("Failed to restore blocked item \(item.logString): \(error)")
            }
        }

        MenuBarItemManager.diagLog.info("Restore completed: \(blockedItems.count - failedMoves)/\(blockedItems.count) blocked items restored")

        try? await Task.sleep(for: .milliseconds(200))

        return failedMoves
    }
}
