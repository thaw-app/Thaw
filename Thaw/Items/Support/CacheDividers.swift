//
//  CacheDividers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// The dividers for passes that work off the item cache, which drops them. On macOS 27 a collapsed
/// divider has no accessibility element, so without a walked pair the pass gets stand-ins, whose window
/// IDs let a frame check tell them from a real divider macOS parked off the bar.
nonisolated enum CacheDividers {
    /// Below the high bit every synthetic accessibility window ID sets, and far above the IDs
    /// the window server hands out, so no walked item ever carries one.
    static let standInHiddenWindowID: CGWindowID = 0x7FFF_FF00

    /// The Always Hidden stand-in's window ID, chosen the same way.
    static let standInAlwaysHiddenWindowID: CGWindowID = 0x7FFF_FF01

    static func pair(
        live: ControlItemPair?,
        leadingX: CGFloat,
        alwaysHiddenEnabled: Bool,
        ownerPID: pid_t
    ) -> ControlItemPair {
        live ?? standIns(leadingX: leadingX, alwaysHiddenEnabled: alwaysHiddenEnabled, ownerPID: ownerPID)
    }

    /// Zero-size dividers at the display's leading edge, so every walked item reads as Visible.
    /// The store resolves them by tag and title.
    static func standIns(leadingX: CGFloat, alwaysHiddenEnabled: Bool, ownerPID: pid_t) -> ControlItemPair {
        func standIn(_ tag: MenuBarItemTag, windowID: CGWindowID, title: String) -> MenuBarItem {
            MenuBarItem(
                tag: tag,
                windowID: windowID,
                ownerPID: ownerPID,
                sourcePID: ownerPID,
                bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                title: title,
                isOnScreen: false
            )
        }
        return ControlItemPair(
            hidden: standIn(.hiddenControlItem, windowID: standInHiddenWindowID, title: ControlItemIdentifier.hidden.rawValue),
            alwaysHidden: alwaysHiddenEnabled
                ? standIn(.alwaysHiddenControlItem, windowID: standInAlwaysHiddenWindowID, title: ControlItemIdentifier.alwaysHidden.rawValue)
                : nil
        )
    }

    static func isStandIn(_ divider: MenuBarItem) -> Bool {
        divider.isControlItem
            && (divider.windowID == standInHiddenWindowID || divider.windowID == standInAlwaysHiddenWindowID)
    }

    /// Nil for stand-ins, which must never pass as live.
    static func live(_ pair: ControlItemPair) -> ControlItemPair? {
        isStandIn(pair.hidden) ? nil : pair
    }

    /// The main screen is only the last fallback: it has the key window, not necessarily the menu bar.
    static func leadingX(display: CGRect?, mainScreen: CGRect?) -> CGFloat {
        display?.minX ?? mainScreen?.minX ?? 0
    }
}
