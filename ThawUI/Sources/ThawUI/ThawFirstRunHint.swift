//
//  ThawFirstRunHint.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A one-line hint for something the user has not done yet.
///
/// One line, dismissed forever, on an accent-washed card so it reads as a
/// note, not a warning. No queue or sequencing; teaching more is onboarding's job.
public struct ThawFirstRunHint: View {
    private let image: Image
    private let title: Text?
    private let text: Text
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?
    private let onDismiss: () -> Void

    /// - Parameters:
    ///   - systemImage: SF Symbol shown before the sentence, in the same
    ///     size as the row's text.
    ///   - text: The one sentence. It wraps rather than truncating, so a
    ///     narrow window still shows the whole instruction.
    ///   - actionTitle: The one thing the hint suggests doing, when there is
    ///     one. A suggestion, unlike a warning, reads as a hint with a button.
    ///   - action: Runs when the suggestion is taken.
    ///   - onDismiss: Called when the close button is pressed. The caller
    ///     records the dismissal; the view holds no state of its own.
    public init(
        systemImage: String,
        _ text: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        image = Image(systemName: systemImage)
        title = nil
        self.text = Text(text)
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    /// A hint with a bold lead line above its sentence, for callers that already hold Text, such as a TipKit tip.
    public init(image: Image, title: Text?, text: Text, onDismiss: @escaping () -> Void) {
        self.image = image
        self.title = title
        self.text = text
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
            .accessibilityLabel("Dismiss hint")
            .help("Dismiss hint")
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
        .thawGlass(.accent(.accentColor), in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same discipline as the warning pill: inside a grouped form the
        // glass card is the row, so the form must not draw one of its own
        // behind it. A no-op anywhere else.
        .listRowBackground(Color.clear)
    }
}
