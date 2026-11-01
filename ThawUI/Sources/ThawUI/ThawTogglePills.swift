//
//  ThawTogglePills.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Switches that turn on and off independently, in the capsule a ThawPillPicker
/// draws, for a row where several choices can be on at once.
public struct ThawTogglePills<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let sizing = ThawTogglePillStyle.sizing
        HStack(spacing: sizing.spacing) {
            content
        }
        .toggleStyle(ThawTogglePillStyle())
        .padding(sizing.inset)
        .thawGlass(.control, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// One switch drawn as a ThawPillPicker segment: filled and heavier while on.
struct ThawTogglePillStyle: ToggleStyle {
    static let sizing = ThawCapsuleSegments<Int>.Sizing.fitted(showsTitles: true)

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        let shape = Capsule(style: .continuous)
        return Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(ThawType.body.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, Self.sizing.horizontalPadding)
                .frame(minWidth: Self.sizing.minWidth, minHeight: Self.sizing.minHeight)
                .thawSelectedFill(isOn, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .thawSelectionCue(isSelected: isOn, in: shape)
        .accessibilityValue(Text(isOn ? LocalizedStringKey("On") : LocalizedStringKey("Off")))
        .accessibilityAddTraits(.isToggle)
    }
}
