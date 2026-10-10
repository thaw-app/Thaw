//
//  ThawRowHover.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Row hover

/// Add an accent wash because hover lift alone is hard to see on plain text buttons.
/// A flat, strokeless hover selection stays distinct from selected rows.
struct ThawRowHover<S: InsettableShape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                if isHovered, isEnabled {
                    Color.clear.thawGlass(.selection(.accentColor, strength: .hover), in: shape)
                }
            }
            .onHover { isHovered = $0 }
            .thawHoverLift()
    }
}

public extension View {
    /// Applies the shared row and plain-button hover treatment, a flat accent
    /// wash in shape plus the hover lift.
    func thawRowHover(in shape: some InsettableShape) -> some View {
        modifier(ThawRowHover(shape: shape))
    }

    /// Applies the shared row and plain-button hover treatment in a rounded
    /// rectangle at the control radius.
    func thawRowHover() -> some View {
        thawRowHover(in: RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
    }
}
