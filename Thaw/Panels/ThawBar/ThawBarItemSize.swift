//
//  ThawBarItemSize.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// How large the Thaw Bar draws its items, as a share of their size in the menu bar.
///
/// A scale of 1 is the menu bar's own size and the default, so a bar looks as it
/// did before the setting existed. Smaller scales fit more items in a row. Only
/// the Thaw Bar reads this; Layout, search and the menu bar overlays keep their sizes.
nonisolated struct ThawBarItemSize: Equatable {
    /// The smallest scale offered. Below it a capture's glyph drops under about
    /// ten points on a notched menu bar.
    static let minimumScale = 0.6

    /// The menu bar's own size. Captures are never drawn larger, since
    /// upscaling a bitmap blurs it.
    static let maximumScale = 1.0

    /// The slider moves in tenths: 60, 70, 80, 90 and 100 percent.
    static let scaleStep = 0.1

    /// The size every bar had before the setting existed.
    static let defaultScale = maximumScale

    static let scaleRange: ClosedRange<Double> = minimumScale ... maximumScale

    /// The height glyphs are first fitted to: the menu bar's height. Nil draws
    /// them at their intrinsic size.
    let fittingHeight: CGFloat?

    /// The chosen scale, clamped to scaleRange.
    let scale: CGFloat

    /// The display's backing scale, so scaled sizes land on whole pixels.
    let displayScale: CGFloat

    init(fittingHeight: CGFloat?, scale: Double = defaultScale, displayScale: CGFloat = 2) {
        self.fittingHeight = fittingHeight
        self.scale = CGFloat(Self.clampedScale(scale))
        self.displayScale = displayScale > 0 ? displayScale : 1
    }

    /// Keeps a stored or typed value in range. Anything that isn't a number is the default.
    static func clampedScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultScale }
        return Swift.min(Swift.max(value, minimumScale), maximumScale)
    }

    /// Whether items are drawn at the menu bar's size, exactly as before the setting.
    var isFullSize: Bool {
        scale >= 1
    }

    /// Rounds to the nearest device pixel, never below one pixel.
    static func pixelAligned(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        let pixels = Swift.max((value * displayScale).rounded(), 1)
        return pixels / displayScale
    }

    /// A glyph's size after fitting, scaled. The height lands on whole pixels
    /// and the width follows it, so captures and app icons shrink by the same
    /// share and keep their shape. Full size returns the fitted size untouched.
    func scaledGlyphSize(_ fitted: CGSize) -> CGSize {
        guard !isFullSize, fitted.width > 0, fitted.height > 0 else { return fitted }
        let height = Self.pixelAligned(fitted.height * scale, displayScale: displayScale)
        let width = Self.pixelAligned(fitted.width * height / fitted.height, displayScale: displayScale)
        return CGSize(width: width, height: height)
    }

    /// The height of one row of items in the vertical and grid arrangements.
    func rowHeight(fitting contentHeight: CGFloat) -> CGFloat {
        guard !isFullSize, contentHeight > 0 else { return contentHeight }
        return Self.pixelAligned(contentHeight * scale, displayScale: displayScale)
    }

    /// The gap between items, scaled with them so a smaller bar keeps its proportions.
    func spacing(_ base: CGFloat) -> CGFloat {
        guard !isFullSize, base > 0 else { return base }
        return (base * scale * displayScale).rounded() / displayScale
    }
}
