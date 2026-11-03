//
//  MenuBarItemSpotlighting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Highlights the real menu bar item found in Thaw's UI so users can locate it.
/// Works across apps using names from the accessibility tree.
@MainActor
public protocol MenuBarItemSpotlighting: AnyObject {
    /// Whether the platform surface exists on this system.
    var isSupported: Bool { get }

    /// Turns the item's spotlight on or off. The item keeps glowing until
    /// turned off, so pair every true with a false.
    @discardableResult
    func setItemSpotlighted(_ spotlighted: Bool, forItemNamed name: String) async -> Bool
}
