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

    /// During first launch, permissions are requested as the final step of
    /// onboarding. Later on — say, if permissions get revoked — this window
    /// shows the permissions step on its own, so re-granting access doesn't
    /// send the user through the whole tour again.
    ///
    /// Both branches render the same view, so the screen a user meets when
    /// permissions are revoked is the one they were onboarded with. Quit is
    /// supplied only here: this window hides its close, minimize and zoom
    /// buttons, and Continue is disabled until the required permissions are
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
