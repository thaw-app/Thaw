//
//  OnboardingPrimaryButton.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The button that moves an onboarding window on: gold, the default action, and
/// the same size on every screen.
public struct OnboardingPrimaryButton<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(action: action) {
            label
                .font(ThawType.heading)
                // A minimum: the titles are translated and a fixed width clips the longer ones.
                .frame(minWidth: 140, minHeight: 34)
        }
        .buttonStyle(.thawProminent)
        .keyboardShortcut(.defaultAction)
    }
}
