//
//  ClickAim.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Where a synthetic click on a menu bar item lands.
enum ClickAim {
    /// The display whose bar this task's clicks aim at, or nil to aim by the pointer. A Thaw Bar
    /// sits below its menu bar, so the pointer that clicked it would not pick that bar.
    @TaskLocal static var barDisplay: CGDirectDisplayID?

    /// The point a synthetic click on bounds should aim at.
    ///
    /// macOS 27 mirrors one status-item set onto every bar but reports its
    /// frames in a single display's space, so a click aimed at the reported
    /// frame lands on the wrong bar when the cursor is on another one. Rebase
    /// the frame onto barDisplay when it is set, else onto the display under
    /// the cursor, the bar the user is looking at. A cursor outside every menu
    /// bar leaves the frame alone, which keeps hotkey and search activation
    /// targeting the item's own bar.
    static func point(for bounds: CGRect) -> CGPoint {
        let displays = NSScreen.allDisplayBoundsCG
        if let barDisplay,
           let point = ClickTargetCheck.clickPoint(for: bounds, onBarOf: CGDisplayBounds(barDisplay), displays: displays)
        {
            return point
        }
        guard
            let pointer = MouseHelpers.locationCoreGraphics,
            let screen = NSScreen.screen(containingCGPoint: pointer),
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return bounds.center
        }
        return ClickTargetCheck.clickPoint(
            for: bounds,
            pointer: pointer,
            display: CGDisplayBounds(screen.displayID),
            menuBarHeight: menuBarHeight,
            displays: displays
        )
    }
}
