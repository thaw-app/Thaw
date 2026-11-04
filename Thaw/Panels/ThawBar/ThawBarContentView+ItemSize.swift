//
//  ThawBarContentView+ItemSize.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension ThawBarItemSize {
    /// A status item's height, which the pictures in the bar are cropped to. An app icon standing in
    /// for a picture is fitted to it, so it isn't smaller than the pictures beside it.
    static let appIconHeight: CGFloat = 24

    /// The size the Thaw Bar draws an item's glyph at: fitted to the menu bar's
    /// height, or an app icon to a picture's, then scaled.
    func glyphSize(for image: MenuBarItemDisplayImage) -> CGSize {
        guard case .appIcon = image else {
            return scaledGlyphSize(image.targetSize(fittingHeight: fittingHeight))
        }
        let intrinsic = image.pointSize
        let limit = min(fittingHeight.flatMap { $0 > 0 ? $0 : nil } ?? Self.appIconHeight, Self.appIconHeight)
        guard intrinsic.height > 0 else { return scaledGlyphSize(intrinsic) }
        // Down only, like every other glyph: a small icon isn't blurred up.
        let fit = min(1, limit / intrinsic.height)
        return scaledGlyphSize(CGSize(width: intrinsic.width * fit, height: intrinsic.height * fit))
    }
}

/// Kept out of ThawBarContentView.swift, which is at its SwiftLint baseline length.
extension ThawBarContentView {
    /// The item size saved for this bar's display.
    var itemSizing: ThawBarItemSize {
        ThawBarItemSize(
            fittingHeight: itemMaxHeight,
            scale: appState.settings.displaySettings.configuration(for: screen.displayID).thawBarItemScale,
            displayScale: screen.backingScaleFactor
        )
    }

    /// One row's height in the vertical and grid arrangements. The horizontal bar
    /// keeps the menu bar's height so it lines up under it.
    var itemRowHeight: CGFloat {
        itemSizing.rowHeight(fitting: contentHeight)
    }
}
