//
//  SimpleModeHowItWorks.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Simple Mode's one-line help, naming a way back that works: the icon only
/// while it shows, otherwise a click in the menu bar, otherwise the shortcut.
nonisolated enum SimpleModeHowItWorks {
    static var hide: String {
        String(localized: "Hold ⌘ and drag icons to the left of the divider in your menu bar to hide them.")
    }

    static func show(showsIcon: Bool, showsOnClick: Bool) -> String {
        if showsIcon {
            String(localized: "Click \(Constants.displayName)'s icon to show them again.")
        } else if showsOnClick {
            String(localized: "Click an empty part of the menu bar to show them again.")
        } else {
            String(localized: "Use your shortcut to show them again.")
        }
    }

    static func text(showsIcon: Bool, showsOnClick: Bool) -> String {
        "\(hide) \(show(showsIcon: showsIcon, showsOnClick: showsOnClick))"
    }
}
