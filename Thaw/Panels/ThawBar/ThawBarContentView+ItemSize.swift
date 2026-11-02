//
//  ThawBarContentView+ItemSize.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension ThawBarItemSize {
    /// The size the Thaw Bar draws an item's glyph at: fitted to the menu bar's
    /// height, then scaled.
    func glyphSize(for image: MenuBarItemDisplayImage) -> CGSize {
        scaledGlyphSize(image.targetSize(fittingHeight: fittingHeight))
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
