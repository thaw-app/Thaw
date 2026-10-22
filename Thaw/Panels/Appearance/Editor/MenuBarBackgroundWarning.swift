//
//  MenuBarBackgroundWarning.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Says when macOS's own menu bar background is on and covers the look.
/// It reads the setting again whenever Thaw comes back, such as from System Settings.
struct MenuBarBackgroundWarning: View {
    @State private var isOn = MenuBarBackgroundSetting.isOn()

    var body: some View {
        Group {
            if isOn {
                SettingsWarningPill(
                    title: "Show menu bar background is on",
                    message: "macOS draws its own background under the menu bar, which covers this look. Turn it off to see your changes.",
                    systemImage: "menubar.rectangle",
                    actionTitle: "Open Menu Bar Settings",
                    action: { Constants.openMenuBarSystemSettings() }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isOn = MenuBarBackgroundSetting.isOn()
        }
    }
}
