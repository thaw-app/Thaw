//
//  NativeAppHidingToggle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Control Center's per-app switch preserves Live Activities and the camera indicator unlike usual hiding.
/// Keep it opt-in while reliability is unproven because it rewrites another app's settings.
struct NativeAppHidingToggle: View {
    @Bindable var settings: AdvancedSettings
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    var body: some View {
        Toggle(isOn: $settings.enableNativeAppHiding) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Show Live Activities and the camera indicator")
                ThawBadge.beta
            }
        }
        .annotation {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                Text(
                    """
                    Keeps Live Activities and the camera indicator on the menu bar while apps are \
                    hidden, and stops hidden items from flashing when Notification Center opens. \
                    While it's on, macOS may show the screen recording indicator when \
                    \(Constants.displayName) updates item pictures.
                    """
                )
                if let fallbackReason {
                    Text("Using the usual hiding for now: \(fallbackReason) Turn this off and on to try again.")
                        .foregroundStyle(.orange)
                }
                if settings.enableNativeAppHiding {
                    feedbackButtons
                }
            }
        }
        if appState.menuBarManager.nativeAppHidingExperiment.previousSessionRecoveryFailed {
            SettingsWarningPill(
                title: "Some apps may still be hidden",
                message: "\(Constants.displayName) couldn't read Control Center's settings at launch, so apps it hid earlier weren't shown again. Restore them from Tools.",
                tint: .orange,
                actionTitle: "Open Tools"
            ) {
                appState.navigationState.settingsNavigationIdentifier = .tools
            }
        }
    }

    /// Why this session went back to the usual hiding while the switch stays
    /// on, or nil when native hiding is running or was never started.
    private var fallbackReason: String? {
        let experiment = appState.menuBarManager.nativeAppHidingExperiment
        guard settings.enableNativeAppHiding, !experiment.isActive else { return nil }
        return experiment.lastError
    }

    /// Praise goes to Discord, where it costs nobody a closed issue; problems
    /// go to GitHub, where they are tracked.
    private var feedbackButtons: some View {
        HStack(spacing: ThawSpacing.compact) {
            Text("How is it working?")
            Button("Tell Us on Discord") { openURL(Constants.discordURL) }
                .buttonStyle(.settingsGlass)
                .help("Opens the \(Constants.displayName) Discord")
            Button("Report a Problem…") { openURL(Self.problemReportURL) }
                .buttonStyle(.settingsGlass)
                .help("Opens a new GitHub issue with your versions filled in")
        }
        .controlSize(.small)
    }

    /// Prefill build and macOS versions so reports include them without manual lookup.
    private static var problemReportURL: URL {
        let body = """
        What happened:

        \(Constants.buildDescription)
        """
        var components = URLComponents(
            url: Constants.issuesURL.appendingPathComponent("new"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Native app hiding: problem"),
            URLQueryItem(name: "body", value: body),
        ]
        return components?.url ?? Constants.issuesURL
    }
}
