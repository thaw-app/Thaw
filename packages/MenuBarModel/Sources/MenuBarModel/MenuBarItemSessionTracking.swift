//
//  MenuBarItemSessionTracking.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation

/// Opens menus through the platform agent without synthetic events or AX round-trips; foreign item IDs are AX titles.
/// Pair startTracking(itemID:) with stopTracking(itemID:); open menus are released only when the session ends.
@MainActor
public protocol MenuBarItemSessionTracking: AnyObject {
    /// Returns whether tracking started; callers must confirm that the menu rendered.
    @discardableResult
    func startTracking(itemID: String) async -> Bool

    /// Stops the tracking session previously opened for itemID.
    @discardableResult
    func stopTracking(itemID: String) async -> Bool

    /// Keyboard navigation between menu bar items while a menu is open.
    @discardableResult
    func navigate(_ direction: Int64) async -> Bool
}
