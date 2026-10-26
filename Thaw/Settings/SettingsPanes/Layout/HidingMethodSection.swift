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
    /// False when the layout cannot be arranged, so the note on moving Apple's pinned items does not apply.
    let offersAppleItems: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var confirmsSetAside = false
    @State private var setAsideError: String?

    private var experiment: NativeAppHidingExperiment {
        appState.menuBarManager.nativeAppHidingExperiment
    }

    private var method: HidingMethod {
        HidingMethod(nativeAppHidingEnabled: settings.enableNativeAppHiding)
    }

    private var methodBinding: Binding<HidingMethod> {
        Binding(
            get: { method },
            set: { newValue in
                guard NativeHidingStart.allowsMethodChange(journalNeedsAttention: experiment.journalNeedsAttention) else {
                    return
                }
                // The Apple-items switch follows: off under Native, on under Standard.
                settings.enableNativeAppHiding = newValue.usesNativeAppHiding
            }
        )
    }

    var body: some View {
        ThawSection {
            Text("Hiding")
        } content: {
            ThawPillPicker("Hiding method", selection: methodBinding, values: HidingMethod.allCases, title: \.localized)
                .disabled(!NativeHidingStart.allowsMethodChange(journalNeedsAttention: experiment.journalNeedsAttention))
                .annotation {
                    VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                        Text(method.explanation)
                        if experiment.journalNeedsAttention {
                            Text("The hiding method can change again once the unreadable record is set aside.")
                                .foregroundStyle(.orange)
                        }
                        if method == .native {
                            nativeStatus
                        } else if let notice = experiment.failedStartNotice {
                            Text(notice)
                                .foregroundStyle(.orange)
                        }
                    }
                }

            if method.hidesAppleItems, offersAppleItems {
                // Blue denotes a limitation, not a failure.
                SettingsWarningPill(
                    title: "Apple's items move differently",
                    message: "macOS 27 draws them itself instead of letting each one place its own icon, so \(Constants.displayName) has to ask macOS to move them rather than moving them directly. Some refuse to move, some return to Visible on their own, and Clock and Control Center can only be hidden together with Siri.",
                    systemImage: "flask.fill",
                    tint: .blue
                )
            }

            if experiment.journalNeedsAttention {
                unreadableRecordNotice
            } else if experiment.previousSessionRecoveryFailed {
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

    /// Asks before setting the unreadable record aside, because the apps it
    /// lists stay switched off and Thaw can no longer tell which ones it hid.
    @ViewBuilder
    private var unreadableRecordNotice: some View {
        SettingsWarningPill(
            title: "Can't read the record of hidden apps",
            message: "\(Constants.displayName) keeps a record of the apps it switches off in System Settings \(Constants.menuArrow) Menu Bar, and that record can't be read. Until you set it aside, \(Constants.displayName) won't show or hide apps that way.",
            tint: .orange,
            actionTitle: "Set Aside…"
        ) {
            setAsideError = nil
            confirmsSetAside = true
        }
        .alert("Set aside the unreadable record?", isPresented: $confirmsSetAside) {
            Button("Set Aside") {
                do {
                    try experiment.setAsideUnreadableRecord()
                } catch {
                    setAsideError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {
                // Closing the alert is all Cancel does; the record stays where it is.
            }
        } message: {
            Text("\(Constants.displayName) keeps the file under a new name and starts a new record. Apps it hid before stay switched off, and you can choose which ones to show afterwards.")
        }
        if let setAsideError {
            Text(setAsideError)
                .foregroundStyle(.orange)
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
        NativeHidingStart.fallbackReason(
            nativeChosen: settings.enableNativeAppHiding,
            isActive: experiment.isActive,
            journalNeedsAttention: experiment.journalNeedsAttention,
            lastError: experiment.lastError
        )
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
