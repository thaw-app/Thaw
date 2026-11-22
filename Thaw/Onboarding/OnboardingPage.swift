//
//  OnboardingPage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// One screen of the onboarding window: its content, then a bar with the page's buttons in the app's
/// own styles, as Thaw's sheets lay them out.
struct OnboardingPage<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(ThawSpacing.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: ThawSpacing.base) {
                footer
            }
            .buttonStyle(.settingsGlass)
            .padding(.horizontal, ThawSpacing.section)
            .padding(.vertical, ThawSpacing.gutter)
        }
        .background(VisualEffectBackground())
    }
}

/// The button that moves the onboarding window on.
struct OnboardingContinueButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.thawProminent)
        .keyboardShortcut(.defaultAction)
    }
}

/// The onboarding window may have no close button, so its pages offer Quit.
struct OnboardingQuitButton: View {
    let help: LocalizedStringResource

    var body: some View {
        Button("Quit \(Constants.displayName)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
        .help(Text(help))
    }
}
