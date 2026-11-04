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
    /// before it settles, so a glyph much shorter than the one the cache has loses. Live items
    /// skip this rule: a graph or a level really can get shorter.
    static nonisolated func preferredRevealedImage(
        existing: MenuBarItemGlyphCapture,
        candidate: MenuBarItemGlyphCapture
    ) -> MenuBarItemGlyphCapture {
        let preferred = preferredCachedImage(existing: existing, candidate: candidate)
        guard preferred.cgImage === candidate.cgImage, !existing.isEffectivelyBlank else { return preferred }
        let existingHeight = inkPointHeight(of: existing)
        guard existingHeight > 0 else { return preferred }
        return inkPointHeight(of: candidate) < existingHeight * revealedInkHeightTolerance ? existing : candidate
    }

    /// The height in points from the first to the last row with visible ink.
    static nonisolated func inkPointHeight(of capture: MenuBarItemGlyphCapture) -> CGFloat {
        let image = capture.cgImage
        let width = image.width, height = image.height
        guard width > 0, height > 0, capture.scale > 0 else { return 0 }
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        let inkRows = (0 ..< height).filter { row in
            (0 ..< width).contains { column in data[(row * width + column) * 4 + 3] > 12 }
        }
        guard let first = inkRows.first, let last = inkRows.last else { return 0 }
        return CGFloat(last - first + 1) / capture.scale
    }
}
