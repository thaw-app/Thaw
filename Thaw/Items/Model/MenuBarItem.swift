//
//  MenuBarItem.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit

typealias MenuBarItem = MenuBarModel.MenuBarItem

// MARK: - MenuBarItem (app-only additions)

extension MenuBarItem {
    nonisolated var displayName: String {
        if let custom = customName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }

        // Thaw's own spacers carry their autosave name as the title; show a
        // human name in the layout editor, search, and menus instead.
        if MenuBarSpacerManager.isSpacerTag(tag) {
            return String(localized: "Spacer")
        }
        if let folder = GroupFolders.label(for: tag) {
            return folder
        }
        if ThawBarOnlyProxies.isProxyTag(tag) {
            return String(localized: "Thaw Bar Only items")
        }
        if let label = ItemStandInSlot.label(for: tag) {
            return label
        }

        return autoDetectedName
    }

    /// Whether the item has a menu or action to launch, rather than being bar
    /// furniture. Used by surfaces that activate items (palette, Shortcuts);
    /// surfaces that arrange the bar keep the bare isControlItem check.
    nonisolated var isUserActionable: Bool {
        !isControlItem
            && !isSystemClone
            && !isTransientControlCenterItem
            && !tag.isNativeOverflowControl
            // Spacers are deliberately not control items so they stay
            // draggable, but there is nothing to launch in one.
            && !(tag.isThawOwnedNamespace
                && tag.title.hasPrefix(MenuBarSpacerManager.autosavePrefix))
            // The launcher opens a bar, and a stand-in's item is listed in
            // its own right.
            && !ThawBarOnlyProxies.isProxyTag(tag)
            && ItemStandInSlot(tag: tag) == nil
    }

    /// Keyed by uniqueIdentifier, not windowID, which changes across app restarts.
    nonisolated var customName: String? {
        get {
            let names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
            return names[uniqueIdentifier]
        }
        set {
            var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
            if let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                names[uniqueIdentifier] = newValue
            } else {
                names.removeValue(forKey: uniqueIdentifier)
            }
            Defaults.set(names, forKey: .menuBarItemCustomNames)
        }
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    struct ListOption: OptionSet {
        let rawValue: Int

        static let onScreen = ListOption(rawValue: 1 << 0)

        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    private static let diagLog = DiagLog(category: "MenuBarItem")

    /// Returns no geometry when a known owner could not be refreshed. Retained
    /// items and position-store recoveries cannot verify a move.
    @MainActor
    static func getFreshMenuBarItemsForMove(priorityPIDs: Set<pid_t> = []) async -> [MenuBarItem]? {
        await MenuBarItemAXProvider.menuBarItemsForMoveConcurrent(priorityPIDs: priorityPIDs)
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass nil to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    @MainActor
    static func getMenuBarItems(
        on display: CGDirectDisplayID? = nil,
        option: ListOption,
        resolveSourcePID: Bool = true,
        freshOnly: Bool = false,
        priorityPIDs: Set<pid_t> = []
    ) async -> [MenuBarItem] {
        diagLog.debug(
            "getMenuBarItems: starting (resolveSourcePID=\(resolveSourcePID))"
        )

        // Items come from each app's AXExtrasMenuBar. The walk stays
        // in-process: the move verify loop runs it too often for the helper.
        // It runs on the concurrent pool so a hung app cannot freeze the UI.
        let axItems = await MenuBarItemAXProvider.menuBarItemsConcurrent(
            on: display, option: option, freshOnly: freshOnly, priorityPIDs: priorityPIDs
        )
        // Items with no extras bar exist only in MenuBarAgent's layout
        // preference (see PositionStoreItemSource). Recovery costs
        // synchronous LaunchServices IPC and adds stale frames, so callers
        // that need only live geometry opt out.
        let items = resolveSourcePID && !freshOnly ? PositionStoreItemSource.recovering(axItems) : axItems
        diagLog.debug("getMenuBarItems: returned \(items.count) items (AX path)")
        return items
    }
}
