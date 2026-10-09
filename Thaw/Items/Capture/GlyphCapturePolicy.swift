//
//  GlyphCapturePolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Glyph Trust And Preference

    /// Minimum point width for a crop that is trusted as a real status-item glyph.
    /// Narrower crops usually come from native overflow chevron bleed on macOS 27.
    static nonisolated let minimumTrustedGlyphWidth: CGFloat = 15

    /// Whether capture is a settled glyph worth keeping over a miss: not
    /// blank, and wide enough not to be native overflow chevron bleed.
    static nonisolated func isTrustedGlyph(_ capture: MenuBarItemGlyphCapture) -> Bool {
        !capture.isEffectivelyBlank && capture.pointSize.width >= minimumTrustedGlyphWidth
    }

    /// Chooses between an existing cache entry and a newly captured candidate.
    ///
    /// Prefers keeping a settled non-blank glyph over blank or much-narrower
    /// replacements (chevron bleed), while still allowing legitimate updates
    /// when the candidate is at least as wide.
    static nonisolated func preferredCachedImage(
        existing: MenuBarItemGlyphCapture,
        candidate: MenuBarItemGlyphCapture
    ) -> MenuBarItemGlyphCapture {
        if existing.isEffectivelyBlank {
            return candidate
        }
        if candidate.isEffectivelyBlank {
            return existing
        }
        if candidate.pointSize.width < existing.pointSize.width * 0.75 {
            return existing
        }
        return candidate
    }

    /// Whether prewarm should recapture an item given its cached image state.
    ///
    /// A glyph loaded from disk counts as present. Each saved entry already
    /// expires by its volatility class on load, and recapturing every saved
    /// glyph meant that one missing item made the Thaw Bar reveal and capture
    /// the whole section, one batch after another.
    static nonisolated func prewarmNeedsCapture(
        cachedImage: MenuBarItemGlyphCapture?,
        wouldAttemptCapture: Bool
    ) -> Bool {
        guard wouldAttemptCapture else { return false }
        guard let cachedImage, !cachedImage.isEffectivelyBlank else { return true }
        // Recover from a native overflow chevron («») stored as a successful crop.
        if cachedImage.pointSize.width < Self.minimumTrustedGlyphWidth {
            return true
        }
        return false
    }

    /// Resolves the capture a consumer would draw for tag, and the key it is
    /// filed under, without touching the access order.
    ///
    /// Falls back to a window-ID-insensitive match because disk-loaded and
    /// idle-trimmed entries carry no window ID or an old one.
    ///
    /// Blank entries resolve to nothing, so every caller treats them as a miss.
    static nonisolated func cachedCapture(
        for tag: MenuBarItemTag,
        in capturesByTag: [MenuBarItemTag: MenuBarItemGlyphCapture]
    ) -> (tag: MenuBarItemTag, capture: MenuBarItemGlyphCapture)? {
        if let capture = capturesByTag[tag], !capture.isEffectivelyBlank {
            return (tag, capture)
        }
        guard !tag.isSystemItem,
              let entry = capturesByTag.first(where: { $0.key.matchesIgnoringWindowID(tag) }),
              !entry.value.isEffectivelyBlank
        else {
            return nil
        }
        return (entry.key, entry.value)
    }
}
