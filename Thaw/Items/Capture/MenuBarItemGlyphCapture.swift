//
//  MenuBarItemGlyphCapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// One menu bar item's pixels as they were read off the screen, paired with the
/// backing scale that was in effect at that moment.
///
/// The scale travels with the bitmap because the cache can outlive a move to
/// a display with a different backing scale.
///
/// Unchecked Sendable: cgImage and scale are immutable, and presentationCache
/// is only touched from main-actor members.
struct MenuBarItemGlyphCapture: Hashable, @unchecked Sendable {
    /// A reference box so the memoized trim survives copies of the value.
    /// Only reached from main-actor members.
    private final class PresentationCache: @unchecked Sendable {
        var horizontallyTrimmedCGImage: CGImage?
        var isSingleInkGlyph: Bool?
    }

    /// The raw crop, sized in device pixels.
    let cgImage: CGImage

    /// The display's backing scale when the crop was taken. Pixels divided
    /// by this give points; it is not necessarily today's scale.
    let scale: CGFloat

    /// The memoized trim derived from this immutable capture.
    private let presentationCache = PresentationCache()

    /// cgImage measured in points rather than device pixels.
    nonisolated var pointSize: CGSize {
        CGSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
    }

    /// The crop with leading and trailing transparency removed. Stays
    /// AppKit-free; wrapping it for a UI framework is the view layer's job.
    ///
    /// Memoized because view bodies read it continuously and each trim walks
    /// the pixel buffer, which outruns the autorelease pool.
    @MainActor
    var horizontallyTrimmedCGImage: CGImage? {
        if let cached = presentationCache.horizontallyTrimmedCGImage {
            return cached
        }
        guard let trimmed = cgImage.trimmingTransparency(around: [
            .minXEdge, .maxXEdge,
        ]) else {
            return nil
        }
        presentationCache.horizontallyTrimmedCGImage = trimmed
        return trimmed
    }

    /// Whether the crop is one ink on transparency, so it can be re-inked
    /// for a background other than the bar it was taken from. See
    /// CGImage.isSingleInkGlyph(maximumChroma:maximumLuminanceSpread:).
    /// Memoized for the same reason as horizontallyTrimmedCGImage.
    @MainActor
    var isSingleInkGlyph: Bool {
        if let cached = presentationCache.isSingleInkGlyph {
            return cached
        }
        let result = cgImage.isSingleInkGlyph()
        presentationCache.isSingleInkGlyph = result
        return result
    }

    /// Whether the capture is effectively blank for UI thumbnail purposes.
    nonisolated var isEffectivelyBlank: Bool {
        cgImage.isTransparent(alphaThreshold: 0.05)
    }

    /// Returns whether two optional captured images have equivalent visual content.
    ///
    /// Uses pointer equality on CGImage as a fast path, falling back to
    /// dimension and pixel-data comparison when instances differ.
    static func isVisuallyEqual(_ old: MenuBarItemGlyphCapture?, _ new: MenuBarItemGlyphCapture?) -> Bool {
        guard let old, let new else { return old == nil && new == nil }
        if old.cgImage === new.cgImage {
            return true
        }
        guard old.scale == new.scale,
              old.cgImage.width == new.cgImage.width,
              old.cgImage.height == new.cgImage.height
        else {
            return false
        }
        guard let oldData = old.cgImage.dataProvider?.data,
              let newData = new.cgImage.dataProvider?.data
        else {
            return false
        }
        return oldData == newData
    }

    static func == (lhs: MenuBarItemGlyphCapture, rhs: MenuBarItemGlyphCapture) -> Bool {
        lhs.cgImage == rhs.cgImage && lhs.scale == rhs.scale
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cgImage)
        hasher.combine(scale)
    }
}
