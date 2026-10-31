//
//  OnboardingIconTile.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import SwiftUI

/// System Settings-style icon tile: a small continuous-corner square filled
/// with a hue behind a white glyph. Decorative, since a name always sits beside it.
public struct OnboardingIconTile: View {
    private let image: Image
    private let tint: Color
    private let side: CGFloat

    public init(image: Image, tint: Color = .accentColor, side: CGFloat = 22) {
        self.image = image
        self.tint = tint
        self.side = side
    }

    public init(symbol: String, tint: Color = .accentColor, side: CGFloat = 22) {
        self.init(image: Image(systemName: symbol), tint: tint, side: side)
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(tint.gradient)
            .frame(width: side, height: side)
            .overlay {
                // Resizable and scaled to fit a fixed inset box: SF Symbol proportions vary per glyph,
                // and font sizing lets wide or tall symbols overflow the tile.
                image
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: side * 0.58, height: side * 0.58)
            }
            .accessibilityHidden(true)
    }
}
