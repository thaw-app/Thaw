//
//  InPlaceMenuOpener.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Opens a concealed item's right-click menu where it sits, through AXShowMenu,
/// so a right click from the Thaw Bar need not reveal the item first.
@MainActor
enum InPlaceMenuOpener {
    static func showMenu(for item: MenuBarItem, pid: pid_t) async -> Bool {
        let snapshot = ClickReactionVerifier.snapshot(for: item)
        let target = (Bridging.getWindowBounds(for: item.windowID) ?? item.bounds).center
        guard await MenuBarAXQueries.showStatusItemMenu(pid: pid, target: target) else {
            return false
        }
        return await ClickReactionVerifier.verifyAllowingLateOpen(against: snapshot).didReact
    }
}
