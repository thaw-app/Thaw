//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Resolve the stage once per opening in onAppear; init cannot read the environment and would retain launch-time state.
/// Holding it in state prevents the "seen" write from switching to recovery before dismissal.
private struct PermissionsFlowView: View {
    @Environment(AppState.self) private var appState
    @State private var stage: OnboardingSequencer.Stage?

    var body: some View {
        Group {
            switch stage {
            case let .onboarding(skipsAccessStep):
                ThawOnboardingView(skipsAccessStep: skipsAccessStep) { outcome, pane in
                    appState.completeOnboarding(outcome: outcome, opening: pane)
                }
            case .recovery:
                ThawPermissionsView {
                    appState.completeFirstLaunchSetup()
                }
            case .none?:
                // Close mistaken openings on the next turn rather than leaving an empty window.
                EmptyView()
                    .onAppear {
                        appState.dismissWindow(.permissions)
                    }
            case nil:
                // Preserve window size without showing the wrong screen while the stage resolves.
                Color.clear
            }
        }
        // Minimum and ideal sizes allow the window to grow with Dynamic Type instead of clipping Larger Text.
        .frame(
            minWidth: ThawOnboardingWindowMetrics.width,
            idealWidth: ThawOnboardingWindowMetrics.width,
            minHeight: ThawOnboardingWindowMetrics.height,
            idealHeight: ThawOnboardingWindowMetrics.height
        )
        .onAppear(perform: resolveStage)
    }

    /// Consume replay once per opening so later permission recovery does not repeat the tour.
    private func resolveStage() {
        guard stage == nil else { return }
        let replayRequested = appState.replayRequested
        appState.replayRequested = false
        stage = OnboardingSequencer.stage(
            hasCompletedFirstLaunch: Defaults.bool(forKey: .hasCompletedFirstLaunch),
            hasSeenOnboarding: Defaults.bool(forKey: .hasSeenOnboarding),
            accessibilityGranted: appState.permissions.permissionsState != .missing,
            seenOnboardingVersion: Defaults.integer(forKey: .onboardingVersion),
            currentOnboardingVersion: Constants.currentOnboardingVersion,
            replayRequested: replayRequested
        )
    }
}

/// The window that hosts onboarding and the access recovery screen.
struct PermissionsWindow: Scene {
    let appState: AppState

    var body: some Scene {
        ThawWindow(id: .permissions, appState: appState) {
            PermissionsFlowView()
                .onWindowChange { window in
                    guard let window else {
                        return
                    }
                    // Closing without required grants would strand the app because even its control item is absent.
                    window.standardWindowButton(.closeButton)?.isHidden =
                        appState.permissions.permissionsState == .missing
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
        // contentMinSize allows resizing beyond the ideal when Larger Text exceeds a step's budget.
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .environment(appState)
        .environment(appState.permissions)
    }
}
