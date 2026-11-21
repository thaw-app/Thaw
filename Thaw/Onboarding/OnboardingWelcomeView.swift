//
//  OnboardingWelcomeView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// The website's headline and terms, with one sentence on what Thaw does.
struct OnboardingWelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        OnboardingWelcomeLayout(continueTitle: Text("Continue"), onContinue: onContinue) {
            // VoiceOver skips the decorative icon because the title identifies the app.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .thawShadow(.hero)
                .accessibilityHidden(true)
        } copy: {
            copyBlock
        } exit: {
            // Offer a quiet exit before permissions so accidental launches need no setup or menu-bar search.
            OnboardingQuietButton(
                title: Text("Quit \(Constants.displayName)"),
                help: Text("Quit \(Constants.displayName) without setting it up"),
                shortcut: KeyboardShortcut("q")
            ) {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var copyBlock: some View {
        Text("Take back your menu bar")
            .font(ThawType.display)
            .multilineTextAlignment(.center)

        Text("\(Constants.displayName) hides the icons you don't need and brings them back with a click on its menu bar icon.")
            .font(ThawType.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440)
            .padding(.top, ThawSpacing.compact)

        OnboardingTermsLine()
            .padding(.top, ThawSpacing.gutter)
    }
}

/// The terms line from under the website's headline, shared by the welcome and the access screen.
struct OnboardingTermsLine: View {
    var body: some View {
        Text("Free under GPL-3.0, with no tracking and no account.")
            .font(ThawType.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
