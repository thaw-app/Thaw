//
//  OnboardingWelcomeLayout.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import SwiftUI

/// The first screen of onboarding: the app's identity and copy centred over the button that moves on, on the
/// window's blend, with a quiet exit in the corner.
public struct OnboardingWelcomeLayout<Hero: View, Copy: View, Exit: View>: View {
    private let continueTitle: Text
    private let onContinue: () -> Void
    private let hero: Hero
    private let copy: Copy
    private let exit: Exit

    public init(
        continueTitle: Text,
        onContinue: @escaping () -> Void,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder copy: () -> Copy,
        @ViewBuilder exit: () -> Exit
    ) {
        self.continueTitle = continueTitle
        self.onContinue = onContinue
        self.hero = hero()
        self.copy = copy()
        self.exit = exit()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Matched spacers center content; minimum spacing handles Larger Text with no spare height.
            Spacer(minLength: ThawSpacing.gutter)

            hero

            // Kept together so the centering spacers move the reading sequence as one block.
            VStack(spacing: 0) {
                copy
            }
            .padding(.top, ThawSpacing.inset)

            OnboardingPrimaryButton(action: onContinue) {
                continueTitle
            }
            .padding(.top, ThawSpacing.section)

            Spacer(minLength: ThawSpacing.gutter)
        }
        .padding(.horizontal, ThawSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A quiet exit before permissions, so nobody has to sit through the setup.
        .overlay(alignment: .bottomTrailing) {
            exit
        }
        .background(VisualEffectBackground())
    }
}

/// The small way out of an onboarding screen, placed for the window's bottom trailing corner.
public struct OnboardingQuietButton: View {
    let title: Text
    let help: Text
    let shortcut: KeyboardShortcut?
    private let action: () -> Void

    /// The help is the tooltip, saying what leaving here does.
    /// The shortcut is a key for it, such as ⌘Q when it quits, since the window may have no close button.
    public init(title: Text, help: Text, shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            title
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .help(help)
        .accessibilityLabel(title)
        .padding(.trailing, ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.inset)
    }
}

/// An onboarding page's title and one paragraph under it, which settle into place when the page appears.
public struct OnboardingHeader: View {
    private let title: Text
    private let message: Text

    @State private var appeared = false

    public init(title: Text, message: Text) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: ThawSpacing.compact) {
            title
                .font(ThawType.display)
                .multilineTextAlignment(.center)

            message
                .font(ThawType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            // A local curve because ThawMotion has no bouncy one.
            withThawAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                appeared = true
            }
        }
    }
}

public extension View {
    /// Settles an onboarding flow onto a new step, and cuts to it under Reduce Motion, transitions included.
    func onboardingStepAnimation(value: some Equatable) -> some View {
        modifier(OnboardingStepAnimation(value: value))
    }
}

private struct OnboardingStepAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content
            .thawAnimation(ThawMotion.settle, value: value)
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }
}
