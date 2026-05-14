//
//  MenuBarTestFixtures.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw

// MARK: - MenuBarItemTag fixtures

extension MenuBarItemTag {
    /// Creates a tag for an ordinary app status item identified by bundle ID and title.
    static func appItem(
        bundleID: String,
        title: String,
        instanceIndex: Int = 0,
        windowID: CGWindowID? = nil
    ) -> MenuBarItemTag {
        MenuBarItemTag(
            namespace: .string(bundleID),
            title: title,
            windowID: windowID,
            instanceIndex: instanceIndex
        )
    }
}

// MARK: - MenuBarItem fixtures

extension MenuBarItem {
    /// Builds a synthetic menu bar item suitable for unit tests of the planner
    /// functions. The defaults produce a movable, hideable, on-screen item.
    static func fixture(
        tag: MenuBarItemTag,
        windowID: CGWindowID,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 24, height: 22),
        sourcePID: pid_t? = 1234,
        ownerPID: pid_t = 1234,
        title: String? = nil,
        isOnScreen: Bool = true
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: sourcePID,
            bounds: bounds,
            title: title ?? tag.title,
            isOnScreen: isOnScreen
        )
    }
}

// MARK: - ControlItemPair fixtures

extension MenuBarItemManager.ControlItemPair {
    /// Builds a synthetic control item pair from explicit rectangles. The
    /// hidden divider is required; the always-hidden divider is optional to
    /// model both layouts (with and without the always-hidden section).
    ///
    /// Default window IDs are deliberately in the 1_000_000+ range so the
    /// underlying Bridging.getWindowBounds lookup (invoked by
    /// CacheContext.bestBounds) reliably misses, forcing the fall-back to
    /// item.bounds. Real macOS window IDs are far smaller, so collisions
    /// would only happen on a system with extreme window pressure.
    static func fixture(
        hiddenAt: CGRect,
        alwaysHiddenAt: CGRect? = nil,
        hiddenWindowID: CGWindowID = 1_000_001,
        alwaysHiddenWindowID: CGWindowID = 1_000_002
    ) -> MenuBarItemManager.ControlItemPair {
        let hidden = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: hiddenWindowID,
            bounds: hiddenAt,
            sourcePID: nil
        )
        let alwaysHidden: MenuBarItem? = alwaysHiddenAt.map { rect in
            MenuBarItem.fixture(
                tag: .alwaysHiddenControlItem,
                windowID: alwaysHiddenWindowID,
                bounds: rect,
                sourcePID: nil
            )
        }
        return MenuBarItemManager.ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)
    }
}
