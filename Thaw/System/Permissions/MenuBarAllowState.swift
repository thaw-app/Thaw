//
//  MenuBarAllowState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// Control Center's own switch for an app's menu bar items, which macOS
/// applies before anything Thaw does.
@MainActor
enum MenuBarAllowState {
    /// Whether either grant that opens Control Center's app list is held.
    private static var canReadList: Bool {
        PickedFileAccess.controlCenterAppList.hasAccess || PickedFileAccess.controlCenterVisibilityRecovery.hasAccess
    }

    /// The switch for Thaw itself, or nil when it cannot be told: the list was
    /// never granted, or has no record of Thaw. Never asks for access.
    static func ofThaw() -> Bool? {
        guard canReadList else { return nil }
        return try? NativeAppVisibilityStore().isAllowed(bundleID: ThawMenuBarIdentity.bundleIdentifier)
    }

    /// The given apps whose switch is off. Empty when the list cannot be read. Never asks for access.
    static func switchedOff(among bundleIDs: Set<String>) -> Set<String> {
        guard !bundleIDs.isEmpty, canReadList else { return [] }
        let store = NativeAppVisibilityStore()
        return bundleIDs.filter { (try? store.isAllowed(bundleID: $0)) == false }
    }
}
