//
//  ThawSpacing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Shared spacing steps. New code uses these, and a literal between two steps rounds to the nearer one.
public enum ThawSpacing {
    /// A hairline gap: badge insets, the space between a glyph and its frame.
    public static let hairline: CGFloat = 2
    /// Between things that belong to one control: a symbol and its label.
    public static let tight: CGFloat = 4
    /// Inside compact chrome: badge and pill padding.
    public static let compact: CGFloat = 6
    /// The default step between siblings.
    public static let base: CGFloat = 8
    /// Vertical rhythm of a row, and the gap between a row's glyph and text.
    public static let row: CGFloat = 10
    /// Inset from a card or field edge to its content.
    public static let inset: CGFloat = 12
    /// Gutter between a pane edge and its column, and between cards.
    public static let gutter: CGFloat = 16
    /// Between sections of a pane.
    public static let section: CGFloat = 24

    /// Between a glass capsule's edge and the segments or buttons it holds.
    public static let capsuleInset: CGFloat = 3
}
