//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Hosts the first-launch onboarding tour, or the standalone permissions view
/// on later launches.
struct PermissionsWindow: Scene {
    let appState: AppState

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
        .environment(appState)
    }

    /// After first launch, shows only the permissions step so re-granting
    /// skips the tour. Quit is supplied here because this window hides its
    /// title bar buttons and Continue stays disabled until permissions are
    /// granted, so it is the only way out for a user who declines.
    @ViewBuilder
    private var permissionsContent: some View {
        if Defaults.bool(forKey: .hasCompletedFirstLaunch) {
            ThawPermissionsView(
                onContinue: { appState.completeFirstLaunchSetup() },
                onQuit: { NSApp.terminate(nil) }
            )
            .frame(width: ThawOnboardingWindowMetrics.width, height: ThawOnboardingWindowMetrics.height)
            .environment(appState.permissions)
        } else {
            ThawOnboardingView {
                Defaults.set(true, forKey: .hasSeenOnboarding)
                appState.completeFirstLaunchSetup()
            }
            .frame(width: ThawOnboardingWindowMetrics.width, height: ThawOnboardingWindowMetrics.height)
            .environment(appState.permissions)
        }
    }
}
