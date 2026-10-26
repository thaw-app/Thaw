//
//  ThawProminentButtonStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The main action of a sheet, step or notice, in the sidebar's selected-row fill and label colour,
/// so the gold never sits under text it makes hard to read.
public struct ThawProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private let tint: Color

    /// - Parameter tint: The fill's colour, the accent unless a notice brings its own.
    public init(tint: Color = .accentColor) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, padding.horizontal)
            .padding(.vertical, padding.vertical)
            .background {
                if isEnabled {
                    // Pressing deepens the fill a step, as the system buttons do.
                    shape.fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
                } else {
                    shape.fill(.quaternary)
                }
            }
            .thawSelectedFill(isEnabled, tint: tint, in: shape)
            .contentShape([.interaction, .focusEffect], shape)
    }

    private var padding: (horizontal: CGFloat, vertical: CGFloat) {
        switch controlSize {
        case .mini: (6, 1)
        case .small: (10, 3)
        case .large, .extraLarge: (16, 8)
        default: (12, 5)
        }
    }
}

public extension ButtonStyle where Self == ThawProminentButtonStyle {
    /// The button that stands out, see ThawProminentButtonStyle.
    static var thawProminent: ThawProminentButtonStyle {
        ThawProminentButtonStyle()
    }

    /// The prominent button tinted with tint instead of the accent.
    static func thawProminent(tint: Color) -> ThawProminentButtonStyle {
        ThawProminentButtonStyle(tint: tint)
    }
}
