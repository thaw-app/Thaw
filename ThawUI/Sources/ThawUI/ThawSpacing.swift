//
//  ThawSpacing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The spacing steps Thaw's views share.
///
/// Read off what the code already did: paddings and stack spacings clustered
/// on 4, 6, 8, 10, 12 and 16 with 24 between sections, so the scale names
/// those steps and nothing else.
///
/// New code takes its spacing from here; existing literals move over when
/// their file is touched for another reason, never in a sweep. A literal
/// between two steps rounds to the nearer one rather than earning a rung.
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
}
