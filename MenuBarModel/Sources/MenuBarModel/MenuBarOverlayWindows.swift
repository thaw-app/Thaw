//
//  MenuBarOverlayWindows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import os.lock

/// The window IDs of Thaw's own menu-bar overlays: the reveal mask and the
/// covers.
///
/// Unregistered, MenuOpenMonitor reads them as an open menu, and concealment
/// (which waits for menus to close) waits on its own mask for minutes.
/// Do not exclude Thaw wholesale: its status item menu must still count as open.
public enum MenuBarOverlayWindows {
    private static let state = OSAllocatedUnfairLock(initialState: Set<CGWindowID>())

    /// The registered IDs, for passing to MenuOpenMonitor explicitly.
    public static var current: Set<CGWindowID> {
        state.withLock { $0 }
    }

    /// Call when the overlay is ordered in. A window number of zero means the
    /// window has no window-server backing yet and is ignored.
    public static func register(_ windowID: CGWindowID) {
        guard windowID != 0 else { return }
        state.withLock { _ = $0.insert(windowID) }
    }

    /// Call when the overlay is ordered out. Window numbers are recycled, so an
    /// ID left behind would silence a real menu later.
    public static func unregister(_ windowID: CGWindowID) {
        guard windowID != 0 else { return }
        state.withLock { _ = $0.remove(windowID) }
    }
}
