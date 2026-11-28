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
    /// Checked by hand: every item's identity reads this, and a Regex match cost tens of microseconds.
    static func withoutTeamIdentifierPrefix(_ bundleID: String) -> Substring {
        let prefix = bundleID.unicodeScalars.prefix(11)
        guard prefix.count == 11, prefix.last == ".",
              prefix.dropLast().allSatisfy({ ("A" ... "Z").contains($0) || ("0" ... "9").contains($0) })
        else {
            return bundleID[...]
        }
        return bundleID[prefix.endIndex...]
    }
}
