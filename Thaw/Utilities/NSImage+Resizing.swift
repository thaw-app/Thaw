//
//  NSImage+Resizing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension NSImage {
    /// Returns a copy of the image redrawn at the given size.
    ///
    /// - Note: The copy preserves isTemplate.
    ///
    /// - Parameter size: The size of the returned image.
    func resized(to size: CGSize) -> NSImage {
        let scaled = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            return true
        }
        scaled.isTemplate = isTemplate
        return scaled
    }
}
