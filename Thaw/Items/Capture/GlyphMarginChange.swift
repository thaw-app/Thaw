//
//  GlyphMarginChange.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Tells a picture retaken after the menu bar's spacing shrank from a crop of something else.
///
/// Spacing only changes the empty space beside an item's icon, so the icon itself keeps its
/// size. MenuBarItemImageCache.preferredCachedImage(existing:candidate:) keeps a picture over a
/// much narrower one, since that is usually a crop of macOS's overflow arrows; on its own, that
/// rule would keep a picture taken at a wider spacing for good.
nonisolated enum GlyphMarginChange {
    /// How far apart, in points, two icons' widths or heights may be and still be the same icon.
    static let inkTolerance: CGFloat = 1

    /// Whether candidate is narrower than existing and shows an icon of the same size, measured
    /// by MenuBarItemImageCache.inkBounds(of:).
    static func onlyMarginsShrank(
        from existing: MenuBarItemGlyphCapture,
        to candidate: MenuBarItemGlyphCapture
    ) -> Bool {
        guard candidate.pointSize.width < existing.pointSize.width,
              let existingInk = MenuBarItemImageCache.inkBounds(of: existing),
              let candidateInk = MenuBarItemImageCache.inkBounds(of: candidate)
        else {
            return false
        }
        return abs(existingInk.width - candidateInk.width) <= inkTolerance
            && abs(existingInk.height - candidateInk.height) <= inkTolerance
    }
}
