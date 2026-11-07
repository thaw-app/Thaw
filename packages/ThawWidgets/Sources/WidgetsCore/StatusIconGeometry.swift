//
//  StatusIconGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Where each part of the icon sits in a square of side points. The arc follows the combined
/// status indicator: the ring is as tall as the icon, open 120° at the bottom, with the bottom row on its circle.
nonisolated struct StatusIconGeometry: Equatable {
    let center: CGPoint
    /// The stroke's centreline.
    let radius: CGFloat
    let lineWidth: CGFloat
    /// The box the center symbol is fitted into.
    let glyphSize: CGSize
    let dotDiameter: CGFloat
    /// The bottom row's centres, left to right.
    let dots: [CGPoint]

    /// The arc's open bottom, centred on straight down.
    static let arcGapDegrees: Double = 120
    /// A dot's width as a fraction of the ring's diameter, about 1.6 times the stroke.
    static let dotFraction: CGFloat = 0.09

    init(side: CGFloat, outer: StatusIconComposition.Outer, style: StatusIconStyle) {
        let lineFraction = style.thickness.lineWidth
        switch outer {
        case .arc:
            // The dots are heavier than the stroke and hang below the ring, so the ring is sized for both to fit.
            let height = side * style.size.fill
            let diameter = height / (1 + Self.dotFraction / 2 - lineFraction / 2)
            lineWidth = diameter * lineFraction
            let ringRadius = (diameter - lineWidth) / 2
            let ringCenter = CGPoint(x: side / 2, y: (side - height) / 2 + diameter / 2)
            radius = ringRadius
            center = ringCenter
            glyphSize = CGSize(width: diameter * 0.44, height: diameter * 0.34)
            dotDiameter = diameter * Self.dotFraction
            // Four dots about 0.16 of the diameter apart, along the ring's own circle.
            let step = 2 * asin(min(1, diameter * 0.16 / (2 * ringRadius)))
            dots = [-1.5, -0.5, 0.5, 1.5].map { offset in
                let angle = Double.pi / 2 - offset * step
                return CGPoint(x: ringCenter.x + ringRadius * cos(angle), y: ringCenter.y + ringRadius * sin(angle))
            }
        case .ring, .none:
            // A closed ring leaves no gap, so it shrinks and the row sits under it.
            let diameter = side * style.size.fill * 0.78
            lineWidth = diameter * lineFraction
            center = CGPoint(x: side / 2, y: side * 0.42)
            radius = (diameter - lineWidth) / 2
            let glyphScale: CGFloat = outer == .none ? 0.6 : 0.44
            glyphSize = CGSize(width: diameter * glyphScale / 0.78, height: diameter * glyphScale * 0.77 / 0.78)
            dotDiameter = side * 0.09
            let rowY = side * 0.9
            dots = [-1.5, -0.5, 0.5, 1.5].map { CGPoint(x: side / 2 + $0 * side * 0.15, y: rowY) }
        }
    }
}
