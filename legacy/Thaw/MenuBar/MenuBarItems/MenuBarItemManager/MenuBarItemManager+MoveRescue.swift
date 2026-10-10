//
//  MenuBarItemManager+MoveRescue.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics

// MARK: - Blocked Item Rescue

extension MenuBarItemManager {
    /// Blocked items sit at x=-1 and can't be interacted with normally.
    nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try exactMoveBounds(for: item)
            return bounds.origin.x == -1
        } catch {
            return false
        }
    }

    /// Rescues an item that got stuck at x=-1 after a move into hidden.
    func validateItemPositionAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async {
        // Only moves targeting the hidden divider; others were placed on purpose.
        switch destination {
        case let .leftOfItem(anchor), let .rightOfItem(anchor):
            guard anchor.tag == .alwaysHiddenControlItem else { return }
        }

        if await isItemBlocked(item) {
            MenuBarItemManager.diagLog.warning("Item \(item.logString) stuck at x=-1 after move - attempting recovery")

            guard let appState else { return }
            guard let hiddenControlItem = appState.menuBarManager.controlItem(withName: .hidden)?.window else {
                MenuBarItemManager.diagLog.error("Cannot recover item: missing hidden control item window")
                return
            }

            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard
                let hiddenWindowID = Self.windowServerID(
                    windowNumber: hiddenControlItem.windowNumber
                ),
                let hiddenMenuBarItem = items.first(where: { $0.windowID == hiddenWindowID })
            else {
                MenuBarItemManager.diagLog.error("Cannot recover item: control item not found in menu bar items")
                return
            }

            do {
                try await move(
                    item: item,
                    to: .rightOfItem(hiddenMenuBarItem),
                    on: displayID,
                    skipInputPause: true
                )
                MenuBarItemManager.diagLog.info("Successfully recovered \(item.logString) from blocked state to visible section")
            } catch {
                MenuBarItemManager.diagLog.error("Failed to recover \(item.logString) from blocked state: \(error)")
            }
        }
    }

    /// Exposes isItemBlocked for drag-failure callers.
    func isItemCurrentlyBlocked(_ item: MenuBarItem) async -> Bool {
        await isItemBlocked(item)
    }

    /// Moves a blocked item just right of the hidden divider. Doesn't retry the
    /// original move; that's up to the caller.
    ///
    /// - Returns: true if the rescue move completed without throwing.
    func rescueBlockedItemToVisible(_ item: MenuBarItem) async -> Bool {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let hiddenMenuBarItem = items.first(matching: .hiddenControlItem) else {
            MenuBarItemManager.diagLog.error("Cannot rescue blocked item \(item.logString): hidden control item not found")
            return false
        }
        do {
            try await move(
                item: item,
                to: .rightOfItem(hiddenMenuBarItem),
                skipInputPause: true,
                options: .init(watchdogTimeout: Self.layoutWatchdogTimeout)
            )
            return true
        } catch {
            MenuBarItemManager.diagLog.error("Failed to rescue blocked item \(item.logString): \(error)")
            return false
        }
    }

    /// The outcome to take when a hidden-section drag's move throws after
    /// the drag handler's resample-and-verify pass.
    nonisolated enum HiddenDragFailureAction: Equatable {
        /// The item landed; verification raced macOS's settle.
        case suppress
        /// Stuck at x=-1: rescue to visible and retry once.
        case rescueAndRetry
        /// The hidden divider couldn't be resolved and recovery is already running.
        /// Show a specific message instead of the raw error.
        case alertControlItemsMissing
        /// Show the raw error.
        case alertGeneric
    }

    /// Precedence: landed beats blocked, blocked beats missing control items.
    static nonisolated func classifyHiddenDragFailure(
        reachedPosition: Bool,
        isBlocked: Bool,
        controlItemsMissing: Bool
    ) -> HiddenDragFailureAction {
        if reachedPosition {
            .suppress
        } else if isBlocked {
            .rescueAndRetry
        } else if controlItemsMissing {
            .alertControlItemsMissing
        } else {
            .alertGeneric
        }
    }
}
