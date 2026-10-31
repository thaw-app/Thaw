//
//  SettingsWarningPill.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Glass alert banner for settings form rows, in the same Liquid Glass chrome as ThawSlider.
/// tint defaults to Color.accentColor, so notices pick up the accent or an explicit info/warning color.
public struct SettingsWarningPill: View {
    private let title: LocalizedStringResource?
    private let message: LocalizedStringResource
    private let systemImage: String
    private let tint: Color
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?
    private let secondaryActionTitle: LocalizedStringResource?
    private let secondaryAction: (() -> Void)?

    /// Single-message banner (title omitted).
    public init(
        message: LocalizedStringResource,
        systemImage: String = "exclamationmark.circle.fill",
        tint: Color = .accentColor
    ) {
        title = nil
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        actionTitle = nil
        action = nil
        secondaryActionTitle = nil
        secondaryAction = nil
    }

    /// Title + supporting message, with up to two trailing actions. The second is an alternative
    /// route to the same outcome, drawn as tinted text so there is still one obvious thing to press.
    public init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String = "exclamationmark.circle.fill",
        tint: Color = .accentColor,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: LocalizedStringResource? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        HStack(alignment: .center, spacing: ThawSpacing.inset) {
            Image(systemName: systemImage)
                // Hierarchical: white disappears on the light tints warnings use
                // (yellow, orange), and the tint itself carries the meaning.
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                if let title {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(message)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if actionTitle != nil || secondaryActionTitle != nil {
                VStack(alignment: .trailing, spacing: ThawSpacing.compact) {
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.thawProminent(tint: tint))
                            .controlSize(.small)
                    }

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(tint)
                            .controlSize(.small)
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, ThawSpacing.inset)
        .thawGlass(.accent(tint), in: shape)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .listRowBackground(Color.clear)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
    }
}
