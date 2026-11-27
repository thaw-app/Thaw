//
//  PrivateSymbolGlyph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Apple's own glyphs for AirDrop and Bluetooth are private system symbols
/// with no public counterpart. They load at runtime where that still works.
enum PrivateSymbolGlyph {
    static func image(named name: String, accessibilityDescription label: String) -> NSImage? {
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:accessibilityDescription:")
        guard NSImage.responds(to: selector) else { return nil }
        return NSImage.perform(selector, with: name, with: label)?.takeUnretainedValue() as? NSImage
    }

    /// Falls back to the rune drawn here: a vertical stroke with two closed
    /// arrowheads on its right and two crossing strokes on its left.
    static func bluetooth(accessibilityDescription label: String) -> NSImage {
        let image = image(named: "bluetooth", accessibilityDescription: label) ?? drawnBluetooth(accessibilityDescription: label)
        image.isTemplate = true
        return image
    }

    private static func drawnBluetooth(accessibilityDescription label: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let x = rect.midX - 1
            let top = rect.midY + 6.5
            let bottom = rect.midY - 6.5
            let right = x + 4
            let left = x - 4
            let rune = NSBezierPath()
            rune.move(to: NSPoint(x: left, y: rect.midY + 3.5))
            rune.line(to: NSPoint(x: right, y: rect.midY - 3))
            rune.line(to: NSPoint(x: x, y: bottom))
            rune.line(to: NSPoint(x: x, y: top))
            rune.line(to: NSPoint(x: right, y: rect.midY + 3))
            rune.line(to: NSPoint(x: left, y: rect.midY - 3.5))
            rune.lineWidth = 1.4
            rune.lineCapStyle = .round
            rune.lineJoinStyle = .round
            NSColor.black.setStroke()
            rune.stroke()
            return true
        }
        image.accessibilityDescription = label
        return image
    }
}
