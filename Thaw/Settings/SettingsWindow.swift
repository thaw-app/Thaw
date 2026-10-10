//
//  SettingsWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsWindowMetrics

/// The window sizes the two settings layouts ask for.
///
/// Simple Mode has no sidebar, so the full window's minimum would stop it
/// shrinking to its single column.
enum SettingsWindowMetrics {
    static let fullMinimum = CGSize(width: 918, height: 600)
    static let fullDefault = CGSize(width: 1018, height: 720)

    /// The reading column plus the gutters ThawForm insets it by. Wider than
    /// this and the column stops growing, so the extra is empty margin.
    static let simpleDefault = CGSize(
        width: SettingsDetailLayout.columnMaxWidth + (SettingsDetailLayout.titleHorizontalInset * 2),
        height: 640
    )

    /// Low enough to let someone shrink past the reading column when they want
    /// the window out of the way; the grouped rows reflow rather than clip.
    static let simpleMinimum = CGSize(width: 560, height: 480)

    static func minimum(simpleMode: Bool) -> CGSize {
        simpleMode ? simpleMinimum : fullMinimum
    }

    static func preferred(simpleMode: Bool) -> CGSize {
        simpleMode ? simpleDefault : fullDefault
    }
}

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    @Bindable var appState: AppState

    var body: some Scene {
        ThawWindow(id: .settings, appState: appState) {
            SettingsView(
                appState: appState,
                navigationState: appState.navigationState,
                generalSettings: appState.settings.general
            )
            .sheet(isPresented: $appState.isUpdateConsentPresented) {
                UpdateConsentSheet { autoDownload in
                    appState.isUpdateConsentPresented = false
                    Defaults.set(true, forKey: .hasSeenUpdateConsent)
                    appState.updatesManager.automaticallyChecksForUpdates = true
                    appState.updatesManager.automaticallyDownloadsUpdates = autoDownload
                    appState.startUpdaterIfNeeded()
                } onDisable: {
                    appState.isUpdateConsentPresented = false
                    Defaults.set(true, forKey: .hasSeenUpdateConsent)
                    appState.updatesManager.automaticallyChecksForUpdates = false
                }
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(
            width: SettingsWindowMetrics.fullDefault.width,
            height: SettingsWindowMetrics.fullDefault.height
        )
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { AppUIZoomCommands() }
        .environment(appState)
        .environment(appState.permissions)
    }
}
