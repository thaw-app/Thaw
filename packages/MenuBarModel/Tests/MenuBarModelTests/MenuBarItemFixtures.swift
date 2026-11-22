//
//  MenuBarItemFixtures.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel

extension MenuBarItem {
    /// An on-screen item whose source is its owner and whose title is the tag's.
    static func fixture(
        _ tag: MenuBarItemTag,
        windowID: CGWindowID = 1,
        ownerPID: pid_t = 700,
        bounds: CGRect = CGRect(x: 1100, y: 0, width: 24, height: 22),
        isOnScreen: Bool = true
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: bounds,
            title: tag.title,
            isOnScreen: isOnScreen
        )
    }

    static func fixture(namespace: MenuBarItemTag.Namespace, title: String = "Item-0") -> MenuBarItem {
        fixture(MenuBarItemTag(namespace: namespace, title: title))
    }

    /// A MenuBarAgent extra, such as a Control Center module.
    static func agent(_ title: String) -> MenuBarItem {
        fixture(namespace: .menuBarAgent, title: title)
    }
}
