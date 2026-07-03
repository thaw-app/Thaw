//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

enum PermissionsFlowStage: Equatable {
    case onboarding
    case permissions

    init(hasSeenOnboarding: Bool, hasCompletedFirstLaunch: Bool) {
        self = if !hasSeenOnboarding, !hasCompletedFirstLaunch {
            .onboarding
        } else {
            .permissions
        }
    }
}

private struct PermissionsFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var stage: PermissionsFlowStage

    init() {
        _stage = State(
            initialValue: PermissionsFlowStage(
                hasSeenOnboarding: Defaults.bool(forKey: .hasSeenOnboarding),
                hasCompletedFirstLaunch: Defaults.bool(forKey: .hasCompletedFirstLaunch)
            )
        )
    }

    var body: some View {
        switch stage {
        case .onboarding:
            ThawOnboardingView(showsCompletionScreen: false) {
                Defaults.set(true, forKey: .hasSeenOnboarding)
                appState.permissions.refreshPermissionsState()
                appState.completeFirstLaunchSetup()
            }
            .frame(width: 608, height: 480)
        case .permissions:
            PermissionsView<AppPermissions>()
        }
    }
}

/// The window that hosts the permissions decision.
struct PermissionsWindow: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        IceWindow(id: .permissions) {
            PermissionsFlowView()
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
}
