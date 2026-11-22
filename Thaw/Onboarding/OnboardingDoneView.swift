//
//  OnboardingDoneView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The last onboarding page: how to hide and show items, and the settings worth choosing on day one.
/// Launch at Login and the shortcut apply at once, as in Settings; the update choice waits for onFinish.
struct OnboardingDoneView: View {
    @Environment(AppState.self) private var appState
    /// Previews pass one that never reaches ServiceManagement.
    var launchAtLogin: LaunchAtLoginSetting?
    let onFinish: (OnboardingOutcome) -> Void

    @State private var automaticUpdates = true

    var body: some View {
        OnboardingWelcomeLayout(continueTitle: Text("Open \(Constants.displayName)"), onContinue: finish) {
            EmptyView()
        } copy: {
            Text("\(Constants.displayName) is in your menu bar")
                .font(ThawType.display)
                .multilineTextAlignment(.center)

            howItWorks
                .padding(.top, ThawSpacing.gutter)

            choices
                .padding(.top, ThawSpacing.section)

            Text("Settings opens next in Simple Mode. For everything else, click All Settings in its toolbar.")
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.top, ThawSpacing.gutter)
        } exit: {
            EmptyView()
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.base) {
            step("hand.draw", SimpleModeHowItWorks.hide)
            step("cursorarrow.click", SimpleModeHowItWorks.show(
                showsIcon: appState.settings.general.showThawIcon,
                showsOnClick: appState.settings.visibility.showOnClick
            ))
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(ThawInk.supporting)
        }
        .font(ThawType.body)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.row) {
            LaunchAtLoginRow(setting: launchAtLogin)
                .toggleStyle(.thawCheckbox)
            if let hotkey = appState.settings.hotkeys.hotkey(withAction: .toggleHiddenSection) {
                HotkeyRecorder(hotkey: hotkey) {
                    Text("Shortcut to show and hide")
                }
                // Outside a Form nothing caps its height, and its symbol grows to fill the page.
                .fixedSize(horizontal: false, vertical: true)
            }
            if Constants.supportsSparkleUpdates {
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                    .toggleStyle(.thawCheckbox)
            }
        }
        .padding(ThawSpacing.gutter)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func finish() {
        onFinish(OnboardingOutcome(automaticUpdates: automaticUpdates))
    }
}

#if DEBUG
    #Preview("How to use") {
        OnboardingDoneView(launchAtLogin: OnboardingPreview.launchAtLogin()) { _ in /* Preview only. */ }
            .environment(OnboardingPreview.appState())
            .onboardingPreviewFrame()
    }
#endif
