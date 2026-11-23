//
//  AppProcessApplication.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The application object of the app process, which never takes a Windows menu.
///
/// AppKit fills the menu set as `windowsMenu` with its window commands when Accessibility reads it, and Thaw
/// reads its own menus on every scan. SwiftUI's Window menu stays in the main menu as a plain menu, so its
/// Close and Minimize items keep ⌘W and ⌘M. The Settings process uses a plain `NSApplication` and keeps its menu.
final class AppProcessApplication: NSApplication {
    override var windowsMenu: NSMenu? {
        get { super.windowsMenu }
        // SwiftUI sets it at launch and again as it updates its menus. Once set, AppKit ignores
        // a later nil, so the menu is never passed on.
        set {}
    }
}
