//
//  ThawBarContentView+ItemSize.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension ThawBarItemSize {
    /// The size the Thaw Bar draws an item's capture or app icon at: fitted to
    /// the menu bar's height as before, then scaled by the item size.
    func glyphSize(for image: MenuBarItemDisplayImage) -> CGSize {
        scaledGlyphSize(image.targetSize(fittingHeight: fittingHeight))
    }
}

/// The bar's item size. Kept out of ThawBarContentView.swift, which is at SwiftLint's grandfathered size.
extension ThawBarContentView {
    /// The item size saved for this bar's display.
    var itemSizing: ThawBarItemSize {
        ThawBarItemSize(
            fittingHeight: itemMaxHeight,
            scale: appState.settings.displaySettings.configuration(for: screen.displayID).thawBarItemScale,
            displayScale: screen.backingScaleFactor
        )
    }

    /// One row in the vertical and grid arrangements. The horizontal bar stays
    /// the menu bar's height, so it still lines up under the menu bar.
    var itemRowHeight: CGFloat {
        itemSizing.rowHeight(fitting: contentHeight)
    }
}
