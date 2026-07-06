//
//  LayoutResetLegacy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - LayoutResetTarget

/// Destination section for a user-initiated layout reset from Settings.
enum LayoutResetTarget {
    case visible
    case hidden
    case alwaysHidden
}

// MARK: - LayoutResetLegacy

extension MenuBarItemManager {
    /// Resets layout to the given section using legacy control-item moves.
    func resetLayout(to target: LayoutResetTarget) async throws -> Int {
        switch target {
        case .hidden:
            try await resetLayoutToFreshState()
        case .visible:
            try await resetLayoutToVisible()
        case .alwaysHidden:
            try await resetLayoutToAlwaysHidden()
        }
    }

    /// Moves every movable, hideable item to the visible section.
    func resetLayoutToVisible() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to visible")

        layoutResetBeginUserOperation()
        defer { layoutResetEndUserOperation() }

        guard appState != nil else {
            throw LayoutResetError.missingAppState
        }

        layoutResetClearPinnedSectionPreferences()

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let controlItems = layoutResetControlItemPair(from: &items) else {
            throw LayoutResetError.missingControlItems
        }

        return try await layoutResetMoveItemsToVisible(
            controlItems: controlItems,
            items: items
        )
    }

    /// Moves every movable, hideable item to the always-hidden section.
    func resetLayoutToAlwaysHidden() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to always-hidden")

        layoutResetBeginUserOperation()
        defer { layoutResetEndUserOperation() }

        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        guard appState.settings.advanced.enableAlwaysHiddenSection else {
            throw LayoutResetError.alwaysHiddenSectionDisabled
        }

        layoutResetClearPinnedSectionPreferences()

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard
            let controlItems = layoutResetControlItemPair(from: &items),
            let alwaysHiddenControl = controlItems.alwaysHidden
        else {
            throw LayoutResetError.missingControlItems
        }

        return try await layoutResetMoveItemsToAlwaysHidden(
            alwaysHiddenControl: alwaysHiddenControl,
            items: items
        )
    }

    private func layoutResetMoveItemsToVisible(
        controlItems: ControlItemPair,
        items: [MenuBarItem]
    ) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.menuBarManager.iceBarPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let hiddenControlBounds = Bridging.getWindowBounds(for: controlItems.hidden.windowID)
            ?? controlItems.hidden.bounds

        func itemsNotInVisible(_ items: [MenuBarItem]) -> [MenuBarItem] {
            items.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                return bounds.minX < hiddenControlBounds.maxX
            }
        }

        func movePass(_ items: [MenuBarItem]) async -> Int {
            var failed = 0
            for item in items {
                do {
                    try await move(
                        item: item,
                        to: .rightOfItem(controlItems.hidden),
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during reset-to-visible: \(error)")
                }
            }
            return failed
        }

        var failedMoves = await movePass(itemsNotInVisible(items))

        try? await Task.sleep(for: .milliseconds(200))

        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        if let refreshedControls = layoutResetControlItemPair(from: &refreshedItems) {
            let refreshedHiddenBounds = Bridging.getWindowBounds(for: refreshedControls.hidden.windowID)
                ?? refreshedControls.hidden.bounds
            let notYetInVisible = refreshedItems.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                return bounds.minX < refreshedHiddenBounds.maxX
            }
            if !notYetInVisible.isEmpty {
                MenuBarItemManager.diagLog.debug("Reset-to-visible pass 2: \(notYetInVisible.count) items not yet in visible section")
                failedMoves += await movePass(notYetInVisible)
            }
        }

        await layoutResetRefreshCachesAfterSectionMoves()
        return failedMoves
    }

    private func layoutResetMoveItemsToAlwaysHidden(
        alwaysHiddenControl: MenuBarItem,
        items: [MenuBarItem]
    ) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.menuBarManager.iceBarPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let alwaysHiddenControlBounds = Bridging.getWindowBounds(for: alwaysHiddenControl.windowID)
            ?? alwaysHiddenControl.bounds

        func itemsNotInAlwaysHidden(_ items: [MenuBarItem]) -> [MenuBarItem] {
            items.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                return bounds.maxX > alwaysHiddenControlBounds.minX
            }
        }

        func movePass(_ items: [MenuBarItem]) async -> Int {
            var failed = 0
            for item in items {
                do {
                    try await move(
                        item: item,
                        to: .leftOfItem(alwaysHiddenControl),
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during reset-to-always-hidden: \(error)")
                }
            }
            return failed
        }

        var failedMoves = await movePass(itemsNotInAlwaysHidden(items))

        try? await Task.sleep(for: .milliseconds(200))

        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        if
            let refreshedControls = layoutResetControlItemPair(from: &refreshedItems),
            let refreshedAlwaysHidden = refreshedControls.alwaysHidden
        {
            let refreshedAlwaysHiddenBounds = Bridging.getWindowBounds(for: refreshedAlwaysHidden.windowID)
                ?? refreshedAlwaysHidden.bounds
            let notYetInAlwaysHidden = refreshedItems.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                return bounds.maxX > refreshedAlwaysHiddenBounds.minX
            }
            if !notYetInAlwaysHidden.isEmpty {
                MenuBarItemManager.diagLog.debug("Reset-to-always-hidden pass 2: \(notYetInAlwaysHidden.count) items not yet in always-hidden section")
                failedMoves += await movePass(notYetInAlwaysHidden)
            }
        }

        await layoutResetRefreshCachesAfterSectionMoves()
        return failedMoves
    }
}
