//
//  OnboardingPrimaryButton.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The button that moves an onboarding window on: gold, the default action, and
/// the same size on every screen.
struct OnboardingPrimaryButton<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(ThawType.heading)
                // A minimum, not a width: the titles are translated and a fixed width clips the longer ones.
                .frame(minWidth: 140, minHeight: 34)
        }
        .buttonStyle(.thawProminent)
        .keyboardShortcut(.defaultAction)
    }
}
