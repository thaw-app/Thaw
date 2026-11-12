//
//  ItemOwnerLookup.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The process a click on an item is aimed at.
///
/// The runtime can list a hidden item with no owner (PID 0). Event taps and
/// Accessibility both need a real process, so every way of opening such an
/// item failed. Its identity still names the app's bundle ID.
nonisolated enum ItemOwnerLookup {
    /// The item's own process, or for an item listed without one, the single
    /// running app its bundle ID names. Two running copies stay ambiguous.
    static func pid(
        for item: MenuBarItem,
        runningPIDs: (String) -> [pid_t] = runningPIDs(forBundleID:)
    ) -> pid_t {
        let pid = item.sourcePID ?? item.ownerPID
        guard pid <= 0, let bundleID = item.tag.namespace.bundleIdentifier else {
            return pid
        }
        let running = runningPIDs(bundleID)
        return running.count == 1 ? running[0] : pid
    }

    /// item with the process pid(for:) finds filled in when it was listed without one. Every check
    /// after a press looks for the item's process: its menu, its drawn entry and the element at its
    /// spot. With PID 0 none of them found anything, so an item that opened counted as a miss.
    static func resolving(
        _ item: MenuBarItem,
        runningPIDs: (String) -> [pid_t] = runningPIDs(forBundleID:)
    ) -> MenuBarItem {
        guard (item.sourcePID ?? item.ownerPID) <= 0 else { return item }
        let pid = pid(for: item, runningPIDs: runningPIDs)
        guard pid > 0 else { return item }
        return MenuBarItem(
            tag: item.tag,
            windowID: item.windowID,
            ownerPID: item.ownerPID > 0 ? item.ownerPID : pid,
            sourcePID: pid,
            bounds: item.bounds,
            title: item.title,
            isOnScreen: item.isOnScreen
        )
    }

    static func runningPIDs(forBundleID bundleID: String) -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
    }
}
