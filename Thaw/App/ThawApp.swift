//
//  ThawApp.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawCapture

@main
@MainActor
enum ThawEntryPoint {
    static func main() {
        if NativeVisibilityRecoveryLaunch.isRequested {
            NativeVisibilityRecoveryApp.main()
        } else {
            ThawApp.main()
        }
    }
}

struct ThawApp: App {
    init() {
        ScreenCapture.setProbeLoggingEnabled {
            Defaults.bool(forKey: .diagnosticRestrictionSceneProbes)
        }
    }

    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        WindowActionBridge(registerWindowActions: appDelegate.appState.registerWindowActions)
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
        WhatsNewWindow(appState: appDelegate.appState)
        AcknowledgementsWindow(appState: appDelegate.appState)
    }
}
