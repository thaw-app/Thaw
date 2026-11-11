//
//  RevealedGlyphPreference.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

extension MenuBarItemImageCache {
    /// How much shorter, in points, a revealed item's new glyph may be before it is taken
    /// for one still scaling in.
    static nonisolated let revealedInkHeightTolerance: CGFloat = 0.8

    /// preferredCachedImage(existing:candidate:) for a picture taken while revealing a hidden
    /// item. Under Native hiding the reveal rebuilds the bar, which draws the icon scaled down
    /// before it settles, so a glyph much shorter than the one the cache has loses. The rebuild
    /// can also catch the glyph mid-slide, its left part not drawn yet or cut off at the crop's
    /// left edge, so such a candidate loses here too. Live items skip these rules: a graph or a
    /// level really can get shorter or lose its left ink.
    static nonisolated func preferredRevealedImage(
        existing: MenuBarItemGlyphCapture,
        candidate: MenuBarItemGlyphCapture
    ) -> MenuBarItemGlyphCapture {
        let preferred = preferredCachedImage(existing: existing, candidate: candidate)
        guard preferred.cgImage === candidate.cgImage, !existing.isEffectivelyBlank else { return preferred }
        if isLeadingCut(candidate, of: existing) || isNewlyClipped(candidate, comparedTo: existing) {
            return existing
        }
        let existingHeight = inkPointHeight(of: existing)
        guard existingHeight > 0 else { return preferred }
        return inkPointHeight(of: candidate) < existingHeight * revealedInkHeightTolerance ? existing : candidate
    }

    /// Whether candidate has the existing picture's crop width but, unlike it, ink running into the left
    /// edge. An item that changed width is a new picture.
    static nonisolated func isNewlyClipped(_ candidate: MenuBarItemGlyphCapture, comparedTo existing: MenuBarItemGlyphCapture) -> Bool {
        abs(candidate.pointSize.width - existing.pointSize.width) < 1
            && isClippedAtLeadingEdge(candidate) && !isClippedAtLeadingEdge(existing)
    }

    /// The height in points from the first to the last row with visible ink.
    static nonisolated func inkPointHeight(of capture: MenuBarItemGlyphCapture) -> CGFloat {
        inkBounds(of: capture)?.height ?? 0
    }
}
