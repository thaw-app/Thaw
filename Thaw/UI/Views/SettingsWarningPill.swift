//
//  SettingsWarningPill.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Glass alert banner for settings form rows.
///
/// Uses the same Liquid Glass chrome as ``IceSlider``, tinted with
/// `tint` (defaults to `Color.accentColor`) so notices pick up the
/// app/system accent — or an explicit info/warning color.
struct SettingsWarningPill: View {
    private let title: LocalizedStringKey?
    private let message: LocalizedStringKey
    private let systemImage: String
    private let tint: Color
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    /// Single-message banner (title omitted).
    init(
        message: LocalizedStringKey,
        systemImage: String = "exclamationmark.circle.fill",
        tint: Color = .accentColor
    ) {
        title = nil
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        actionTitle = nil
        action = nil
    }

    /// Title + supporting message, with an optional trailing action.
    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        systemImage: String = "exclamationmark.circle.fill",
        tint: Color = .accentColor,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, tint)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(message)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Light tint wash over clear glass — reads like the mock's milky
        // translucent pill, not a solid fill.
        .glassEffect(.clear.tint(tint.opacity(0.18)), in: shape)
        .overlay {
            shape.strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.12), radius: 10, y: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .listRowBackground(Color.clear)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}
