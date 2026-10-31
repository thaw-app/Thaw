//
//  ThawFirstRunHint.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A one-line hint for something the user has not done yet, dismissed forever, on an accent-washed
/// card so it reads as a note. No queue or sequencing; teaching more is onboarding's job.
public struct ThawFirstRunHint: View {
    private let image: Image
    private let title: Text?
    private let text: Text
    let dismissLabel: LocalizedStringResource
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?
    private let onDismiss: () -> Void

    /// The text wraps rather than truncating, so a narrow window still shows the whole instruction. The dismiss label is the
    /// close button's help and VoiceOver name. The caller records the dismissal from onDismiss; the view holds no state.
    public init(
        systemImage: String,
        _ text: LocalizedStringResource,
        dismissLabel: LocalizedStringResource,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        image = Image(systemName: systemImage)
        title = nil
        self.text = Text(text)
        self.dismissLabel = dismissLabel
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    /// A hint with a bold lead line above its sentence, for callers that already hold Text, such as a TipKit tip.
    public init(image: Image, title: Text?, text: Text, dismissLabel: LocalizedStringResource, onDismiss: @escaping () -> Void) {
        self.image = image
        self.title = title
        self.text = text
        self.dismissLabel = dismissLabel
        actionTitle = nil
        action = nil
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.row) {
            HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.row) {
                image
                    .font(ThawType.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                    title?
                        .font(ThawType.caption.weight(.semibold))
                    text
                        .font(ThawType.caption)
                }
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: ThawSpacing.base)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(ThawType.micro.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(dismissLabel))
            .help(Text(dismissLabel))
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
        .thawGlass(.accent(.accentColor), in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Inside a grouped form the glass card is the row, so the form must
        // not draw one of its own behind it. A no-op anywhere else.
        .listRowBackground(Color.clear)
    }
}
