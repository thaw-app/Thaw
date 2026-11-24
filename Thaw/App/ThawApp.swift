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
        } else if MemoryBench.isRequested {
            MemoryBench.run()
        } else {
            // Both the app and the Settings process configure TipKit here, before any scene or default changes.
            FeatureTips.configureAtLaunch()
            if SettingsProcessApp.isRequested {
                SettingsProcessApp.main()
            } else {
                TestHosting.isolatePreferencesWhenHosted()
                // NSApp must be created as the subclass before SwiftUI first asks for it.
                _ = AppProcessApplication.shared
                // Before the first status item exists, or macOS seats Thaw's items with its own spacing.
                OwnStatusItemSpacing.install()
                ResidentBench.startAfterLaunchIfRequested()
                ThawApp.main()
            }
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
