//
//  OnboardingCard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// What an onboarding card is drawn on.
public enum OnboardingCardSurface: Sendable {
    /// A flat fill and a hairline, for a window whose vibrancy is the only glass the page needs.
    case flat
    /// The panel tier of ThawGlass.
    case glass
}

public extension View {
    /// The surface an onboarding page's cards share.
    @ViewBuilder
    func onboardingCard(_ surface: OnboardingCardSurface = .flat) -> some View {
        let shape = RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
        switch surface {
        case .flat:
            background(shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
                .clipShape(shape)
        case .glass:
            thawGlass(.panel, in: shape)
        }
    }
}

/// One permission as a card: what it is, what it is for, and the control that changes it, held to the bottom
/// so a row of cards lines its controls up. The app brings the three, since each has its own permission model.
public struct OnboardingPermissionCard<Label: View, Details: View, Control: View>: View {
    private let surface: OnboardingCardSurface
    private let spacing: CGFloat
    private let isGranted: Bool
    private let label: Label
    private let details: Details
    private let control: Control

    /// isGranted animates the card when the grant changes.
    public init(
        surface: OnboardingCardSurface,
        spacing: CGFloat = ThawSpacing.inset,
        isGranted: Bool,
        @ViewBuilder label: () -> Label,
        @ViewBuilder details: () -> Details,
        @ViewBuilder control: () -> Control
    ) {
        self.surface = surface
        self.spacing = spacing
        self.isGranted = isGranted
        self.label = label()
        self.details = details()
        self.control = control()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            label

            details
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            control
        }
        .padding(ThawSpacing.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onboardingCard(surface)
        .thawAnimation(ThawMotion.settle, value: isGranted)
    }
}
