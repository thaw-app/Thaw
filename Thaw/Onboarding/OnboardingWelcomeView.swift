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
        VStack(spacing: 0) {
            // Matched spacers center content; minimum spacing handles Larger Text with no spare height.
            Spacer(minLength: ThawSpacing.gutter)

            // VoiceOver skips the decorative icon because the title identifies the app.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .thawShadow(.hero)
                .accessibilityHidden(true)

            copyBlock
                .padding(.top, ThawSpacing.inset)

            Button(action: onContinue) {
                Text("Continue")
                    .font(ThawType.heading)
                    // A fixed width clips longer translations; use a minimum.
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, ThawSpacing.section)

            Spacer(minLength: ThawSpacing.gutter)
        }
        .padding(.horizontal, ThawSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Offer a quiet exit before permissions so accidental launches need no setup or menu-bar search.
        .overlay(alignment: .bottomTrailing) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit \(Constants.displayName)")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .help("Quit \(Constants.displayName) without setting it up")
            .accessibilityLabel(Text("Quit \(Constants.displayName)"))
            .padding(.trailing, ThawSpacing.gutter)
            .padding(.bottom, ThawSpacing.inset)
        }
        .background(VisualEffectBackground())
    }

    /// Keep the reading sequence together so centering spacers move it as one block.
    private var copyBlock: some View {
        VStack(spacing: 0) {
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
    }

    /// Present pre-permission facts in one glanceable row.
    private var factsRow: some View {
        HStack(spacing: ThawSpacing.base) {
            fact(
                symbol: "lock.open",
                label: Text("Open source"),
                spoken: Text("Free and open source")
            )
            fact(
                symbol: "hand.raised",
                label: Text("No analytics or tracking"),
                // Updates and release notes make outbound calls; claim no analytics, not "nothing leaves your Mac".
                spoken: Text("No analytics, no tracking")
            )
            fact(
                symbol: "record.circle",
                label: Text("Screen Recording optional"),
                spoken: Text("Screen Recording is optional")
            )
            fact(
                symbol: "globe",
                label: Text("20 languages"),
                spoken: Text("Speaks 20 languages")
            )
        }
        .frame(maxWidth: 560)
    }

    /// Scale long translations rather than wrapping one capsule taller than its neighbours.
    private func fact(symbol: String, label: Text, spoken: Text) -> some View {
        HStack(spacing: ThawSpacing.compact) {
            Image(systemName: symbol)
                .font(ThawType.symbol)
                .foregroundStyle(.secondary)

            label
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, ThawSpacing.inset)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .thawGlass(.control, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }
}
