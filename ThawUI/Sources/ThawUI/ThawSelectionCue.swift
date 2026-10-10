//
//  ThawSelectionCue.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Differentiate Without Color adds a leading bar or control ring to accent-only selection.
/// Always set the selected trait so VoiceOver announces state regardless of the visual cue.
public extension View {
    /// Row selection uses a leading bar under Differentiate Without Color.
    func thawSelectionCue(isSelected: Bool) -> some View {
        modifier(ThawSelectionBarCue(isSelected: isSelected))
    }

    /// Shaped control selection uses a ring under Differentiate Without Color.
    func thawSelectionCue(isSelected: Bool, in shape: some InsettableShape) -> some View {
        modifier(ThawSelectionRingCue(isSelected: isSelected, shape: shape))
    }
}

private struct ThawSelectionBarCue: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if isSelected, differentiateWithoutColor {
                    Capsule(style: .continuous)
                        .fill(.primary)
                        .frame(width: ThawSpacing.hairline)
                        .padding(.vertical, ThawSpacing.tight)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThawSelectionRingCue<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let isSelected: Bool
    let shape: S

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelected, differentiateWithoutColor {
                    shape.strokeBorder(.primary, lineWidth: 1.5)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
