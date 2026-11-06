//
//  AirDropGlyph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The AirDrop stand-in's icon.
///
/// Apple's AirDrop glyph is a private system symbol with no public
/// counterpart. It is loaded from the system at runtime where that still
/// works, and otherwise drawn here to the same outline: a dot on a short stem
/// inside three arcs that open at the bottom.
enum AirDropGlyph {
    static func image(accessibilityDescription label: String) -> NSImage {
        let image = systemImage(accessibilityDescription: label) ?? drawn(accessibilityDescription: label)
        image.isTemplate = true
        return image
    }

    private static func systemImage(accessibilityDescription label: String) -> NSImage? {
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:accessibilityDescription:")
        guard NSImage.responds(to: selector) else { return nil }
        return NSImage.perform(selector, with: "airdrop", with: label)?.takeUnretainedValue() as? NSImage
    }

    private static func drawn(accessibilityDescription label: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY + 0.5)
            NSColor.black.set()

            // Open at the bottom: each arc runs from -50° round the top to 230°.
            for radius: CGFloat in [3.2, 5.4, 7.6] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: -50, endAngle: 230)
                arc.lineWidth = 1.2
                arc.lineCapStyle = .round
                arc.stroke()
            }

            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
            dot.fill()

            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: center.x - 1, y: center.y - 1))
            stem.line(to: NSPoint(x: center.x + 1, y: center.y - 1))
            stem.line(to: NSPoint(x: center.x, y: center.y - 4.5))
            stem.close()
            stem.fill()
            return true
        }
        image.accessibilityDescription = label
        return image
    }
}
