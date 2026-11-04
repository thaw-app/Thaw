//
//  CGRect+NaturalFit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

extension CGRect {
    /// A rect of `size` centered in this one, scaled down to fit but never up, so a glyph isn't stretched or blurred.
    /// Returns this rect unchanged when `size` has no area.
    nonisolated func centeredRect(forNaturalSize size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(1, width / size.width, height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: midX - (fitted.width / 2),
            y: midY - (fitted.height / 2),
            width: fitted.width,
            height: fitted.height
        )
    }
}
