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
    /// The switch for Thaw itself, or nil when it cannot be told: the list was
    /// never granted, or has no record of Thaw. Never asks for access.
    static func ofThaw() -> Bool? {
        guard PickedFileAccess.controlCenterAppList.hasAccess
            || PickedFileAccess.controlCenterVisibilityRecovery.hasAccess
        else { return nil }
        return try? NativeAppVisibilityStore().isAllowed(bundleID: ThawMenuBarIdentity.bundleIdentifier)
    }
}
