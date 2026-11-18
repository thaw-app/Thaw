//
//  RevealedGlyphPreference.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

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
    ///
    /// recordedItemWidth is the width Thaw had for the item before the reveal, and listedItemWidth the
    /// width its item list has now, read again since. When the cached picture no longer matches either
    /// (see oldPictureIsStale), a much narrower picture may replace it.
    static nonisolated func preferredRevealedImage(
        existing: MenuBarItemGlyphCapture,
        candidate: MenuBarItemGlyphCapture,
        recordedItemWidth: CGFloat? = nil,
        listedItemWidth: CGFloat? = nil
    ) -> MenuBarItemGlyphCapture {
        let isStale = oldPictureIsStale(existing, itemWidths: [recordedItemWidth, listedItemWidth])
        let preferred = preferredCachedImage(existing: existing, candidate: candidate, oldPictureIsStale: isStale)
        guard preferred.cgImage === candidate.cgImage, !existing.isEffectivelyBlank else { return preferred }
        if isLeadingCut(candidate, of: existing) || isNewlyClipped(candidate, comparedTo: existing) {
            return existing
        }
        let existingHeight = inkPointHeight(of: existing)
        guard existingHeight > 0 else { return preferred }
        return inkPointHeight(of: candidate) < existingHeight * revealedInkHeightTolerance ? existing : candidate
    }

    /// Stores a revealed item's new picture unless preferredRevealedImage keeps the one cached for it.
    /// The cached one is found whatever window ID it is filed under, since a picture loaded from disk
    /// has none; a lookup by the revealed item's own tag missed it, and every new picture won,
    /// including one cut off mid-slide. The picture kept is filed under the revealed item's tag.
    /// - Returns: Whether the cache changed.
    @discardableResult
    func storeRevealedPicture(
        _ picture: MenuBarItemGlyphCapture,
        of item: MenuBarItem,
        listedWidths: [MenuBarItemTag: CGFloat]
    ) -> Bool {
        guard let cached = Self.cachedCapture(for: item.tag, in: capturesByTag) else {
            setCapture(picture, for: item.tag)
            CaptureDiagnostics.recordStored(picture.cgImage, item: item)
            return true
        }
        let preferred = Self.preferredRevealedImage(existing: cached.capture, candidate: picture, revealing: item, listedWidths: listedWidths)
        guard !MenuBarItemGlyphCapture.isVisuallyEqual(preferred, cached.capture) else {
            // A picture loaded from disk was never saved this session; the export shows what the Thaw Bar keeps.
            CaptureDiagnostics.recordStored(preferred.cgImage, item: item, replacing: false)
            // This build saw the item and kept the earlier build's picture, so it stops asking for a retake.
            guard cached.capture.isFromEarlierBuild else { return false }
            setCapture(cached.capture.confirmedByThisBuild, for: cached.tag)
            return true
        }
        if cached.tag != item.tag {
            removeCapture(for: cached.tag)
        }
        setCapture(preferred, for: item.tag)
        CaptureDiagnostics.recordStored(preferred.cgImage, item: item)
        return true
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
