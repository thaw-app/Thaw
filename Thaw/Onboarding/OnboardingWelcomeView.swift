//
//  OnboardingWelcomeView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// "The new" addresses upgraders too, since the shared bundle identifier's onboarding flag can outlive an earlier tour.
/// Capsules fit or scale uneven label lengths, with fuller claims in accessibility labels; matched spacers center the stack in the 580pt area.
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
        Text("Welcome to the new \(Constants.displayName)")
            .font(ThawType.display)
            .multilineTextAlignment(.center)

        Text("\(Constants.displayName) hides the icons you don't need and brings them back with a click on its menu bar icon.")
            .font(ThawType.heading)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440)
            .padding(.top, ThawSpacing.compact)

        // Give the longest passage more width to avoid many short lines.
        Text("\(Constants.displayName) 3 is rebuilt for macOS 27: a new settings window, keyboard search across your menu bar, and rules that bring an item back when you need it.")
            .font(ThawType.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 540)
            .padding(.top, ThawSpacing.inset)

        factsRow
            .padding(.top, ThawSpacing.gutter)
    }

    /// Present pre-permission facts in one glanceable row.
    private var factsRow: some View {
        OnboardingFactRow {
            OnboardingFactCapsule(
                symbol: "lock.open",
                label: Text("Open source"),
                spoken: Text("Free and open source")
            )
            OnboardingFactCapsule(
                symbol: "hand.raised",
                label: Text("No analytics or tracking"),
                // Updates and release notes make outbound calls; claim no analytics, not "nothing leaves your Mac".
                spoken: Text("No analytics, no tracking")
            )
            OnboardingFactCapsule(
                symbol: "record.circle",
                label: Text("Screen Recording optional"),
                spoken: Text("Screen Recording is optional")
            )
            OnboardingFactCapsule(
                symbol: "globe",
                label: Text("20 languages"),
                spoken: Text("Speaks 20 languages")
            )
        }
    }
}
