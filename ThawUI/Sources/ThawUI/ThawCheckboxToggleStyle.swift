//
//  ThawCheckboxToggleStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A checkbox drawn like the sidebar's selected row: the see-through gold
/// fill with a checkmark in the label colour, where macOS would fill it solid gold.
public struct ThawCheckboxToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    private static let side: CGFloat = 14
    private static let shape = RoundedRectangle(cornerRadius: ThawRadius.small, style: .continuous)

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: ThawSpacing.compact) {
                box(isOn: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : ThawInk.disabledOpacity)
        .accessibilityValue(Text(configuration.isOn ? LocalizedStringKey("On") : LocalizedStringKey("Off")))
        .accessibilityAddTraits(.isToggle)
    }

    @ViewBuilder
    private func box(isOn: Bool) -> some View {
        if isOn {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: Self.side, height: Self.side)
                .thawGlass(.selection(.accentColor, strength: .selected), in: Self.shape)
        } else {
            Self.shape
                .strokeBorder(.secondary, lineWidth: 1)
                .frame(width: Self.side, height: Self.side)
        }
    }
}

public extension ToggleStyle where Self == ThawCheckboxToggleStyle {
    /// A checkbox in the sidebar's selection style, see ThawCheckboxToggleStyle.
    static var thawCheckbox: ThawCheckboxToggleStyle {
        ThawCheckboxToggleStyle()
    }
}
