//
//  LayoutBarItemView+ModuleGlyph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension LayoutBarItemView {
    /// App icons fill the available square, but Thaw's own control-item image, its
    /// stand-ins' symbols and an icon the user chose keep their glyph size.
    static func overflowFallbackDrawRect(
        for item: MenuBarItem,
        imageSize: CGSize,
        bounds: CGRect,
        isChosenIcon: Bool = false
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let keepsGlyphSize = isChosenIcon || item.tag.matchesVisibleControlItem || ThawExtraGlyph.isStandIn(item.tag)
        if keepsGlyphSize, imageSize.width > 0, imageSize.height > 0 {
            return bounds.centeredRect(forNaturalSize: imageSize)
        }

        let side = min(bounds.width, bounds.height)
        return (drawsBareModuleGlyph(for: item) ? bareGlyphRect(for: imageSize, in: bounds) : nil) ?? CGRect(
            x: bounds.midX - (side / 2),
            y: bounds.midY - (side / 2),
            width: side,
            height: side
        )
    }

    /// A system module Thaw switched off is never drawn, so its symbol stands in for the picture, without the box.
    static func drawsBareModuleGlyph(for item: MenuBarItem) -> Bool {
        item.tag.namespace == .menuBarAgent && SystemModuleGlyph.symbolName(forItemTitle: item.tag.title) != nil
    }

    /// How strongly a bare module symbol is drawn: full, or dimmed on a tile that can't be used.
    static func bareGlyphFraction(isEnabled: Bool) -> CGFloat {
        isEnabled ? 1 : 0.67
    }

    /// Where a bare module symbol is drawn: as large as fits the tile's centered square, at the symbol's
    /// own proportions. Symbols aren't square (Wi-Fi is 18 by 13), so filling the square squeezed them.
    static func bareGlyphRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect? {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return nil }
        let longest = max(imageSize.width, imageSize.height)
        let scale = longest > 0 ? side / longest : 0
        let size = scale > 0 ? CGSize(width: imageSize.width * scale, height: imageSize.height * scale) : CGSize(width: side, height: side)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}
