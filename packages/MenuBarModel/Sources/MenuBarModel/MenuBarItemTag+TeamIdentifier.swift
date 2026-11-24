//
//  MenuBarItemTag+TeamIdentifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension MenuBarItemTag {
    /// Drops a leading team identifier, such as `Y93TK974AT.` in the Mac App Store
    /// iStat Menus helper `Y93TK974AT.com.bjango.istatmenus-mas.status`, so bundle
    /// matchers see the same ID as in the direct-download build.
    static func withoutTeamIdentifierPrefix(_ bundleID: String) -> Substring {
        guard let match = bundleID.prefixMatch(of: /[A-Z0-9]{10}\./) else {
            return bundleID[...]
        }
        return bundleID[match.range.upperBound...]
    }
}
