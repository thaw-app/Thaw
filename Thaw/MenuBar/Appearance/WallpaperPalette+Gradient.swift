//
//  WallpaperPalette+Gradient.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension WallpaperPalette {
    /// A gradient of the two dominant swatches, or nil before a capture names both.
    /// Repeated swatches give a flat tint for a single-colour wallpaper.
    func gradient(opacity: CGFloat) -> NSGradient? {
        guard let primary, let secondary else {
            return nil
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let start = primary.cgColor(in: colorSpace),
            let end = secondary.cgColor(in: colorSpace),
            let startColor = NSColor(cgColor: start)?.withAlphaComponent(opacity),
            let endColor = NSColor(cgColor: end)?.withAlphaComponent(opacity)
        else {
            return nil
        }
        return NSGradient(starting: startColor, ending: endColor)
    }
}
