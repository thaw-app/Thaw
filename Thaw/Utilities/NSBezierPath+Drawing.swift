//
//  NSBezierPath+Drawing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension NSBezierPath {
    /// Fills a blurred silhouette of the path into the current graphics
    /// context.
    ///
    /// - Parameters:
    ///   - color: The color of the shadow.
    ///   - radius: The blur radius of the shadow.
    func drawShadow(color: NSColor, radius: CGFloat) {
        guard elementCount > 0, let cgContext = NSGraphicsContext.current?.cgContext else {
            return
        }

        cgContext.saveGState()
        defer {
            cgContext.restoreGState()
        }

        // Widen the clip by the blur radius, or the shadow is cut off flush
        // with the path it is supposed to spread out from.
        cgContext.clip(to: bounds.insetBy(dx: -radius, dy: -radius))
        cgContext.setShadow(offset: .zero, blur: radius, color: color.cgColor)
        cgContext.setFillColor(NSColor.black.cgColor)
        cgContext.addPath(cgPath)
        cgContext.fillPath(using: windingRule == .evenOdd ? .evenOdd : .winding)
    }

    /// Returns a path covering every region covered by this path or the given
    /// path.
    ///
    /// - Parameters:
    ///   - other: The path to combine with this one.
    ///   - windingRule: The rule that decides what counts as inside a path.
    func union(_ other: NSBezierPath, using windingRule: WindingRule = .evenOdd) -> NSBezierPath {
        let fillRule: CGPathFillRule = windingRule == .nonZero ? .winding : .evenOdd
        return NSBezierPath(cgPath: cgPath.union(other.cgPath, using: fillRule))
    }
}
