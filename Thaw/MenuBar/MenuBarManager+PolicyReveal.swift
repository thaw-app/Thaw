//
//  MenuBarManager+PolicyReveal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarManager {
    /// Thaw does this by itself, so the reveal is marked as policy and its repairs don't count as user input.
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
