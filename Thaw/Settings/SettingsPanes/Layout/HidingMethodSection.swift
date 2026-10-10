//
//  HidingMethodSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The one place to choose how items are hidden, with what each method gives and costs.
///
/// Native rewrites another app's settings and is still unproven, so it stays opt-in and carries the beta badge.
struct HidingMethodSection: View {
    @Bindable var settings: AdvancedSettings
    /// False when the layout cannot be arranged, which leaves Apple's pinned items out of reach too.
    let offersAppleItems: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    private var method: HidingMethod {
        HidingMethod(
            nativeAppHidingEnabled: settings.enableNativeAppHiding,
            hidesAppleItems: settings.enableExperimentalSystemItemHiding
        )
    }

    private var methodBinding: Binding<HidingMethod> {
        Binding(
            get: { method },
            set: { newValue in
                // Native first: turning it on clears the Apple-items switch, and that switch refuses to turn on beside it.
                settings.enableNativeAppHiding = newValue.usesNativeAppHiding
                settings.enableExperimentalSystemItemHiding = newValue.hidesAppleItems
            }
        )
    }

    private var offeredMethods: [HidingMethod] {
        HidingMethod.allCases.filter { offersAppleItems || !$0.hidesAppleItems || $0 == method }
    }

    var body: some View {
        ThawSection {
            Text("Hiding")
        } content: {
            ThawPicker("Hiding method", selection: methodBinding) {
                ForEach(offeredMethods) { method in
                    Text(method.localized).tag(method)
                }
            }
            .annotation {
                VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                    Text(method.explanation)
                    if method == .native {
                        nativeStatus
                    }
                }
            }

            if method.hidesAppleItems {
                // Blue denotes a limitation, not a failure.
                SettingsWarningPill(
                    title: "Apple's items move differently",
                    message: "macOS 27 draws them itself instead of letting each one place its own icon, so \(Constants.displayName) has to ask macOS to move them rather than moving them directly. Some refuse to move, some return to Visible on their own, and Clock and Control Center can only be hidden together with Siri.",
                    systemImage: "flask.fill",
                    tint: .blue
                )
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
    }

    /// The beta badge, why this session fell back to Standard, and where to send feedback.
    @ViewBuilder
    private var nativeStatus: some View {
        ThawBadge.beta
        if let fallbackReason {
            Text("Using Standard for now: \(fallbackReason) Choose Standard and then Native to try again.")
                .foregroundStyle(.orange)
        }
        feedbackButtons
    }

    /// Why this session went back to Standard while Native stays chosen, or nil when Native is running.
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
