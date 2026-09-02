//
//  ThawBarBorderShape.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A rounded rectangle whose stroke can omit the top edge.
///
/// Used by the Thaw Bar when square corners meet the display's rounded
/// screen corners (#325): drawing the top edge would be clipped and look
/// broken, so only the leading, trailing, and bottom edges are stroked.
struct ThawBarBorderShape: Shape {
    /// Corner radius of the un-inset clip path.
    var cornerRadius: CGFloat
    /// Matches ``ThawBarChrome``'s clip: circular for fully rounded ends,
    /// continuous for square corners.
    var cornerStyle: RoundedCornerStyle = .continuous
    /// When `true`, the path starts at the top-leading corner, runs down the
    /// leading side, across the bottom, and up the trailing side — leaving the
    /// top edge open.
    var omitTopEdge: Bool
    /// Inset applied before constructing the path (half the stroke width so
    /// the stroke sits on the clip edge, matching `InsettableShape.inset`).
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let drawRect = rect.insetBy(dx: inset, dy: inset)
        let radius = min(max(cornerRadius - inset, 0), min(drawRect.width, drawRect.height) / 2)

        if !omitTopEdge {
            return RoundedRectangle(cornerRadius: radius, style: cornerStyle)
                .path(in: drawRect)
        }

        guard radius > 0 else {
            var path = Path()
            path.move(to: CGPoint(x: drawRect.minX, y: drawRect.minY))
            path.addLine(to: CGPoint(x: drawRect.minX, y: drawRect.maxY))
            path.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.maxY))
            path.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.minY))
            return path
        }

        // Continuous corners approximate a squircle; for the open-top path we
        // still stroke circular arcs of the same radius so the visible edges
        // meet the clip cleanly for both styles.
        var path = Path()
        // Top-leading → down the leading edge → bottom-leading arc →
        // bottom edge → bottom-trailing arc → up the trailing edge →
        // top-trailing. No top edge.
        path.move(to: CGPoint(x: drawRect.minX, y: drawRect.minY))
        path.addLine(to: CGPoint(x: drawRect.minX, y: drawRect.maxY - radius))
        path.addArc(
            center: CGPoint(x: drawRect.minX + radius, y: drawRect.maxY - radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: drawRect.maxX - radius, y: drawRect.maxY))
        path.addArc(
            center: CGPoint(x: drawRect.maxX - radius, y: drawRect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.minY))
        return path
    }
}
