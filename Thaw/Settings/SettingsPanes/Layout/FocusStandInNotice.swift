//
//  FocusStandInNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// macOS 27 hides Focus while any item is hidden. When Control Center is set to show it and Thaw isn't
/// standing in for it, Layout says so and offers the stand-in.
struct FocusStandInNotice: View {
    @Bindable var settings: AdvancedSettings
    /// Read by the caller, so tests don't depend on this Mac's Control Center settings.
    let focusShownInControlCenter: Bool

    var body: some View {
        if Self.shows(
            focusShownInControlCenter: focusShownInControlCenter,
            focusReplaced: settings.controlCenterReplacements.isReplaced(.focus)
        ) {
            SettingsWarningPill(
                title: "Focus is hidden",
                message: "macOS hides Focus while items are hidden. \(Constants.displayName) can show its own Focus icon instead.",
                systemImage: "moon.fill",
                tint: .orange,
                actionTitle: "Show Focus",
                action: { Self.replaceFocus(in: &settings.controlCenterReplacements) }
            )
        }
    }

    static func shows(focusShownInControlCenter: Bool, focusReplaced: Bool) -> Bool {
        focusShownInControlCenter && !focusReplaced
    }

    /// Replaces Focus alone; the other modules stay as they were.
    static func replaceFocus(in replacements: inout ControlCenterReplacements) {
        replacements.setReplaced(.focus, true)
    }

    /// Whether Control Center is set to show Focus in the menu bar.
    static func focusShownInControlCenter() -> Bool {
        SystemExtraTakeoverCoordinator.isShownInMenuBar(
            MenuBarItemTag(namespace: .menuBarAgent, title: "com.apple.menuextra.focusmode").tagIdentifier
        )
    }
}
