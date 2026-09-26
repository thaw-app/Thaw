//
//  LayoutResetCommand.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The persisted half of a layout reset, runnable before the app builds a
/// menu bar.
///
/// ``MenuBarItemManager/resetLayoutToFreshState()`` also does the live half,
/// which needs a running `AppState`. A parked divider is restored from
/// `NSStatusItem Preferred Position` at launch, so a wrecked bar can start
/// moving items before Settings is reachable (#899). This repairs it first:
///
///     /Applications/Thaw.app/Contents/MacOS/Thaw --reset-layout
///
/// Only `UserDefaults` is touched; run it while the app is not running, or
/// the live manager writes its state back.
enum LayoutResetCommand {
    /// The argument that selects this command.
    static let flag = "--reset-layout"

    /// The defaults keys holding the persisted arrangement.
    ///
    /// Mirrors what `resetLayoutToFreshState()` clears. Removed rather than
    /// zeroed so the loaders fall back to their own defaults.
    static let layoutDefaultsKeys = MenuBarItemManager.LayoutStateKey.all + [
        Defaults.Key.newItemsSection.rawValue,
        Defaults.Key.newItemsPlacementData.rawValue,
        Defaults.Key.staleIdentifierMissCounts.rawValue,
        Defaults.Key.staleIdentifierMissCountsBuild.rawValue,
    ]

    /// Whether the given process arguments select this command.
    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    /// Clears the persisted arrangement and re-seeds the divider positions.
    ///
    /// Matches `resetLayoutToFreshState()`: visible to 0, hidden to 1, and
    /// always-hidden untouched since it is placed dynamically.
    static func resetPersistedLayout() {
        for key in layoutDefaultsKeys {
            Defaults.store.removeObject(forKey: key)
        }
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        ControlItemDefaults.resetChevronPositions()
    }

    /// Runs the command if the arguments select it, reporting whether it
    /// ran so the caller can skip starting the app.
    ///
    /// Writes are flushed explicitly because the process exits right after.
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard isRequested(arguments: arguments) else {
            return false
        }
        resetPersistedLayout()
        Defaults.store.synchronize()
        print("Thaw: menu bar layout reset. Start Thaw again to rebuild it.")
        return true
    }
}
