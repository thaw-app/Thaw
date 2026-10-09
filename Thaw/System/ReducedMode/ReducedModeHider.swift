//
//  ReducedModeHider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// What the reduced mode asks the kit to hide. The call into the kit is in ReducedModeHider+Live.swift.
extension ReducedModeHider {
    /// The kit conceals identifiers, each owned by a bundle. The reduced mode has no items,
    /// so it gives every app one stand-in identifier.
    nonisolated static func input(
        hiding bundleIDs: Set<String>
    ) -> (assignment: [String: MenuBarSectionName], owners: [String: String]) {
        var assignment = [String: MenuBarSectionName]()
        var owners = [String: String]()
        for bundleID in bundleIDs {
            let identifier = "reduced:\(bundleID)"
            assignment[identifier] = .hidden
            owners[identifier] = bundleID
        }
        return (assignment, owners)
    }
}
