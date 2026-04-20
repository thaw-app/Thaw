//
//  SettingsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    @ObservedObject var appState: AppState
    @StateObject private var model = SettingsWindowModel()

    var body: some Scene {
        IceWindow(id: .settings) {
            SettingsView(appState: appState, navigationState: appState.navigationState)
                .onWindowChange { window in
                    model.observeWindowToolbar(window)
                }
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
                .frame(minWidth: 850, minHeight: 550)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 850, height: 550)
        .environmentObject(appState)
    }
}

// MARK: - SettingsWindowModel

@MainActor
private final class SettingsWindowModel: ObservableObject {
    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Configures observers for the window's toolbar.
    func observeWindowToolbar(_ window: NSWindow?) {
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

        guard let window else {
            return
        }

        Publishers.CombineLatest3(
            window.publisher(for: \.toolbar),
            window.publisher(for: \.toolbar?.displayMode),
            window.publisher(for: \.toolbar?.allowsDisplayModeCustomization)
        )
        .sink { toolbar, _, _ in
            toolbar?.displayMode = .iconOnly
            toolbar?.allowsDisplayModeCustomization = false
        }
        .store(in: &cancellables)
    }
}
