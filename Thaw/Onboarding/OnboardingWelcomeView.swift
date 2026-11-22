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
        OnboardingPage {
            VStack(spacing: 0) {
                // VoiceOver skips the decorative icon because the title identifies the app.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .thawShadow(.hero)
                    .accessibilityHidden(true)

                Text("Take back your menu bar")
                    .font(ThawType.display)
                    .multilineTextAlignment(.center)
                    .padding(.top, ThawSpacing.inset)

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
        } footer: {
            // Before permissions, so an accidental launch needs no setup or menu bar search.
            OnboardingQuitButton(help: "Quit \(Constants.displayName) without setting it up")
            Spacer()
            OnboardingContinueButton(title: "Continue", action: onContinue)
        }
    }
}

/// The terms line from under the website's headline.
struct OnboardingTermsLine: View {
    var body: some View {
        Text("Free under GPL-3.0, with no tracking and no account.")
            .font(ThawType.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
    #Preview("Welcome") {
        OnboardingWelcomeView(onContinue: { /* Preview only. */ })
            .onboardingPreviewFrame()
    }
#endif
