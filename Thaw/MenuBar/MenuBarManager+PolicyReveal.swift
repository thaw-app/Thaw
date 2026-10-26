//
//  MenuBarManager+PolicyReveal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarManager {
    /// Puts the bar in the state always-show asks for, one section revealed or none.
    /// Thaw does this by itself, so the reveal is marked as policy and its repairs are not counted as user input.
    func presentAlwaysShowTarget(_ target: MenuBarSectionName?) {
        revealAttribution.policy {
            if let target {
                sectionController.show(target)
            } else {
                sectionController.hideRevealedSections()
            }
        }
    }
}
