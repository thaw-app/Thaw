//
//  LayoutResetCommand.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The persisted half of a layout reset, runnable before the app builds a
/// menu bar.
///
/// ``MenuBarItemManager/resetLayoutToFreshState()`` — the Settings pane's
/// reset — does this plus the live half: re-seating items, re-caching, and
/// ending the settling window. That needs a running `AppState`, and it
/// throws `LayoutResetError.missingAppState` without one.
///
/// The failure this exists for is the one where that is no help. A parked
/// divider persists as an `NSStatusItem Preferred Position` and is restored
/// on the next launch, so a bar wrecked badly enough comes back wrecked and
/// starts moving items — and the pointer — before the user can reach
/// Settings. #899's reporter had to kill Thaw from a terminal; this lets
/// them repair the bar from the same terminal, before starting it again:
///
///     /Applications/Thaw.app/Contents/MacOS/Thaw --reset-layout
///
/// Only `UserDefaults` is touched, so it is safe to run with the app not
/// running, and pointless to run while it is (the live manager holds the
/// same state in memory and will persist it back).
enum LayoutResetCommand {
    /// The argument that selects this command.
    static let flag = "--reset-layout"

    /// The defaults keys holding the persisted arrangement.
    ///
    /// Mirrors what `resetLayoutToFreshState()` clears in memory before
    /// persisting: the saved order, the "seen this item before" set, the
    /// pinning sets, and the in-flight relocation bookkeeping. Removed
    /// rather than zeroed so the loaders fall back to their own defaults.
    static let layoutDefaultsKeys = [
        "MenuBarItemManager.savedSectionOrder",
        "MenuBarItemManager.knownItemIdentifiers",
        "MenuBarItemManager.pinnedHiddenBundleIDs",
        "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs",
        "MenuBarItemManager.pendingRelocations",
        "MenuBarItemManager.pendingReturnDestinations",
    ]

    /// Whether the given process arguments select this command.
    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    /// Clears the persisted arrangement and re-seeds the divider positions.
    ///
    /// The divider half matches `resetLayoutToFreshState()` exactly: visible
    /// to 0, hidden to 1, always-hidden left alone because it is placed
    /// dynamically and has no seed value to restore.
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
    /// Writes are flushed explicitly: the process returns from `main`
    /// immediately after this, and a reset that does not reach disk is
    /// worse than no reset at all — the user would relaunch into the same
    /// wrecked bar believing they had fixed it.
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
