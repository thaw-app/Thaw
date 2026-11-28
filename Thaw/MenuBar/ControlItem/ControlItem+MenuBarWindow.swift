//
//  ControlItem+MenuBarWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension ControlItem {
    /// The control item's window while the item is in the menu bar.
    ///
    /// Before macOS 26 a removed status item (a disabled section's divider)
    /// keeps its window, which must not be read as a live section boundary.
    var menuBarWindow: NSWindow? {
        isAddedToMenuBar ? window : nil
    }
}

extension MenuBarManager {
    /// Whether the always-hidden divider exists but is out of the menu bar, as it is while its section is off.
    var isAlwaysHiddenDividerRemoved: Bool {
        controlItem(withName: .alwaysHidden).map { !$0.isAddedToMenuBar } ?? false
    }
}
