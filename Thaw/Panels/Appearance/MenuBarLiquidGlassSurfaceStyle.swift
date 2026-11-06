//
//  MenuBarLiquidGlassSurfaceStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

extension MenuBarLiquidGlassContainerView {
    /// The color laid over the glass, used only when isColored is set.
    struct Tint {
        var isColored: Bool
        var color: CGColor
        var opacity: Double
    }

    /// The stroke drawn along the shape; a nil color draws none.
    struct Border {
        static let none = Border(color: nil, width: 0)

        var color: CGColor?
        var width: Double
        var style: MenuBarBorderStyle = .solid
    }
}
