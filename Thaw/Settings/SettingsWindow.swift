//
//  SettingsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        IceWindow(id: .settings) {
            SettingsView(appState: appState, navigationState: appState.navigationState)
                .sheet(isPresented: $appState.isUpdateConsentPresented) {
                    UpdateConsentSheet { autoDownload in
                        appState.isUpdateConsentPresented = false
                        Defaults.set(true, forKey: .hasSeenUpdateConsent)
                        appState.updatesManager.automaticallyChecksForUpdates = true
                        appState.updatesManager.automaticallyDownloadsUpdates = autoDownload
                        appState.startUpdaterIfNeeded()
                        appState.presentOnboardingIfNeeded()
                    } onDisable: {
                        appState.isUpdateConsentPresented = false
                        Defaults.set(true, forKey: .hasSeenUpdateConsent)
                        appState.updatesManager.automaticallyChecksForUpdates = false
                        appState.presentOnboardingIfNeeded()
                    }
                }
                .sheet(isPresented: $appState.isOnboardingPresented) {
                    ThawOnboardingView(showsCompletionScreen: false) {
                        Defaults.set(true, forKey: .hasSeenOnboarding)
                        appState.isOnboardingPresented = false
                    }
                    .frame(width: 608, height: 480)
                }
                .frame(minWidth: 850, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 950, height: 650)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .environmentObject(appState)
    }
}
