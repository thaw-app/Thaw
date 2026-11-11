//
//  MenuBarItemIdentityAccessors.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics

public extension MenuBarItem {
    /// uniqueIdentifier in its canonical form, the key every saved order, assignment and lookup is stored under.
    /// Comparing raw identifiers misses an item whose title changes, such as a clock.
    var canonicalIdentifier: String {
        MenuBarItemTag.canonicalPersistentIdentifier(uniqueIdentifier)
    }
}

public extension MenuBarItemTag.Namespace {
    /// The owning app's bundle identifier, which is what a string namespace holds; nil for the other kinds.
    var bundleIdentifier: String? {
        switch self {
        case let .string(string): string
        case .null, .uuid: nil
        }
    }
}

public extension Bridging {
    /// The display the menu bar is attached to, or the main display when the window server names none.
    static var activeMenuBarDisplayID: CGDirectDisplayID {
        getActiveMenuBarDisplayID() ?? CGMainDisplayID()
    }
}
