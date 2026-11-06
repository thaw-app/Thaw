//
//  NSStatusItem+Menu.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension NSStatusItem {
    /// Pops the given menu open from the status item's button, then puts the
    /// item's own menu back.
    ///
    /// A status item only knows how to show the menu it is holding, so the
    /// given menu is swapped in for the duration of the click.
    @MainActor
    func showMenu(_ menu: NSMenu) {
        let previousMenu = self.menu
        defer {
            self.menu = previousMenu
        }
        self.menu = menu
        button?.performClick(nil)
    }
}
