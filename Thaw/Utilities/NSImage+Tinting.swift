//
//  NSImage+Tinting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension NSImage {
    /// Resolves a template image into a concrete color for direct AppKit
    /// drawing, matching the automatic tinting performed by an NSStatusItem.
    func tinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
