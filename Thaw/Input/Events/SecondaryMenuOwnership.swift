//
//  SecondaryMenuOwnership.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Who a right-click on empty menu bar space belongs to: Thaw's menu or MenuBarAgent's.
nonisolated enum SecondaryMenuOwnership {
    /// Option opens Thaw's menu even when MenuBarAgent opens its own, which a plain
    /// right-click on empty menu bar space does from macOS 27.2.
    static func overridesMenuBarAgent(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }

    /// The processes whose open menus must not stop Thaw's menu for this click.
    static func ignoredMenuOwners(
        modifierFlags: NSEvent.ModifierFlags,
        menuBarAgentPIDs: () -> [pid_t] = liveMenuBarAgentPIDs
    ) -> Set<pid_t> {
        overridesMenuBarAgent(modifierFlags: modifierFlags) ? Set(menuBarAgentPIDs()) : []
    }

    static func liveMenuBarAgentPIDs() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: SharedConstants.menuBarHostingBundleID)
            .map(\.processIdentifier)
    }
}
