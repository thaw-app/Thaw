//
//  LayoutBarItemView+ModuleGlyph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension LayoutBarItemView {
    /// A system module Thaw switched off is never drawn, so its symbol stands in for the picture, without the box.
    static func drawsBareModuleGlyph(for item: MenuBarItem) -> Bool {
        item.tag.namespace == .menuBarAgent && SystemModuleGlyph.symbolName(forItemTitle: item.tag.title) != nil
    }

    /// The centered square a bare module symbol is drawn in, the tile's full height as the previews draw it.
    static func bareGlyphRect(in bounds: CGRect) -> CGRect? {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return nil }
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }
}
