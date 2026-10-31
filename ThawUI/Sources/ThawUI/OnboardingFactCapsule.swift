//
//  OnboardingFactCapsule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// One short fact in a glass capsule. Long translations scale rather than wrap, so every capsule
/// in a row keeps the same height; spoken carries the fuller claim.
public struct OnboardingFactCapsule: View {
    private let symbol: String
    private let label: Text
    private let spoken: Text

    public init(symbol: String, label: Text, spoken: Text) {
        self.symbol = symbol
        self.label = label
        self.spoken = spoken
    }

    public var body: some View {
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

/// Facts in one glanceable row of equal capsules. maxWidth suits how many the app shows.
public struct OnboardingFactRow<Content: View>: View {
    private let maxWidth: CGFloat
    private let content: Content

    public init(maxWidth: CGFloat = 560, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: ThawSpacing.base) {
            content
        }
        .frame(maxWidth: maxWidth)
    }
}
