//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The window that hosts the permissions decision — either the first-launch
/// onboarding tour or, on later launches, the standalone permissions view.
struct PermissionsWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        IceWindow(id: .permissions) {
            permissionsContent
                .onWindowChange { window in
                    guard let window else {
                        return
                    }
                    window.standardWindowButton(.closeButton)?.isHidden = true
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                    if let contentView = window.contentView {
                        withMutableCopy(of: contentView.safeAreaInsets) { insets in
                            insets.bottom = -insets.bottom
                            insets.left = -insets.left
                            insets.right = -insets.right
                            insets.top = -insets.top
                            contentView.additionalSafeAreaInsets = insets
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .environmentObject(appState)
        .environmentObject(appState.permissions)
    }

    /// During first launch, permissions are requested as the final step of
    /// onboarding. Later on — say, if permissions get revoked — this window
    /// shows the standalone permissions view instead, so re-granting access
    /// doesn't send the user through the whole tour again.
    @ViewBuilder
    private var permissionsContent: some View {
        if Defaults.bool(forKey: .hasCompletedFirstLaunch) {
            PermissionsView<AppPermissions>()
        } else {
            OnboardingSheet {
                Defaults.set(true, forKey: .hasSeenOnboarding)
            }
        }
    }
}
