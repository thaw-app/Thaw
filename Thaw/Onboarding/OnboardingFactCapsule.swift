//
//  OnboardingFactCapsule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// One short fact in a glass capsule, as the welcome and permission screens
/// show them in a row. Long translations scale rather than wrap, so every
/// capsule in a row keeps the same height; spoken carries the fuller claim.
struct OnboardingFactCapsule: View {
    let symbol: String
    let label: Text
    let spoken: Text

    var body: some View {
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
