//
//  MenuBarItemRowImage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - Item image

/// An item in a list row, as Layout draws it: its menu bar picture, else its app icon.
/// A one-colour picture takes the row's ink, so a white glyph stays readable.
struct MenuBarItemRowImage: View {
    @Environment(AppState.self) private var appState
    /// Grows with Larger Text. Menu bar pictures don't: scaling them up blurs them.
    @ScaledMetric(relativeTo: .body) private var iconBox = PanelRow.iconBox

    /// A menu bar glyph's height, so pictures sit in the row as on the bar.
    private static let glyphHeight: CGFloat = 18
    /// The widest a picture is drawn, so a long text item leaves room for its name.
    private static let maxWidth: CGFloat = 120

    let item: MenuBarItem
    /// A fixed column the picture is centred in and scaled down to fit, so names line up.
    var columnWidth: CGFloat?

    /// The glyph's height-fitted size, scaled down whole when it is wider than limit.
    private static func drawnSize(of image: MenuBarItemDisplayImage, limit: CGFloat) -> CGSize {
        let size = image.targetSize(fittingHeight: glyphHeight)
        guard size.width > limit else { return size }
        return CGSize(width: limit, height: size.height * limit / size.width)
    }

    var body: some View {
        let image = OverflowFallbackIcon.resolvedImage(
            for: item,
            section: appState.menuBarManager.sectionController.section(for: item),
            appState: appState,
            capturedImage: appState.imageCache.image(for: item.tag)
        )
        Group {
            if let image {
                MenuBarItemGlyph(
                    image: image,
                    fittingHeight: Self.glyphHeight,
                    reinksCaptures: true,
                    drawnSize: Self.drawnSize(of: image, limit: columnWidth ?? Self.maxWidth)
                )
                .foregroundStyle(.primary)
            } else {
                MenuBarItemSourceIcon(item: item, length: iconBox)
            }
        }
        .frame(width: columnWidth)
        .frame(minWidth: iconBox, minHeight: iconBox)
    }
}

// MARK: - Source app icon

/// The icon of the app a menu bar item belongs to.
///
/// The same icon the Thaw Bar and Layout fall back to, so a system module such as
/// Bluetooth shows its own symbol. An unresolved owner gets a placeholder.
struct MenuBarItemSourceIcon: View {
    /// Inset for a symbol, so it doesn't look larger than the app icons beside it.
    private static let symbolInset: CGFloat = 4

    let item: MenuBarItem
    let length: CGFloat

    var body: some View {
        if let sourceAppIcon = OverflowFallbackIcon.itemIcon(for: item) {
            Image(nsImage: sourceAppIcon)
                .resizable()
                .scaledToFit()
                .padding(sourceAppIcon.isTemplate ? Self.symbolInset : 0)
                .frame(width: length, height: length)
        } else {
            MenuBarItemPlaceholderIcon(length: length)
        }
    }
}
