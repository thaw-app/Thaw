//
//  IceApp.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The process entry point.
///
/// Wraps ``IceApp`` so command-line invocations can exit before AppKit starts.
/// ``IceApp`` can't: its delegate adaptor builds the whole `AppState` on init.
@main
enum ThawMain {
    static func main() {
        guard !LayoutResetCommand.runIfRequested() else {
            return
        }
        IceApp.main()
    }
}

struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
    }
}
