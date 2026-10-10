//
//  WindowLevelPredicates.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import Foundation
import MenuBarModel

/// Window-level tests shared by the input, overlay and diagnostics paths.
///
/// The pop-up-menu level is read from CoreGraphics, not hard-coded.
nonisolated enum WindowLevelPredicates {
    /// The window level the window server puts open menus on.
    ///
    /// Exact, unlike WindowInfo.isMenuRelated: a persistent overlay at the
    /// level below would read as "open" forever, and there is no baseline here.
    private static let popUpMenuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    /// Whether layer is the window level open menus render at.
    ///
    /// See popUpMenuLevel for why this rejects the level below, which
    /// MenuBarModel.WindowInfo.isMenuRelated accepts.
    static func isPopUpMenu(layer: Int) -> Bool {
        layer == popUpMenuLevel
    }

    /// Whether any window in windows is an open pop-up menu owned by another
    /// process. Thaw's own menus are excluded.
    static func isForeignPopUpMenuOpen(in windows: [WindowInfo]) -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { window in
            window.ownerPID != ownPID && isPopUpMenu(layer: window.layer)
        }
    }
}
