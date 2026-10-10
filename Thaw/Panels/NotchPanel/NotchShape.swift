//
//  NotchShape.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import SwiftUI

/// The descender silhouette: a soft dome hanging below the menu bar, its
/// sides one continuous S-curve from the bar's underside to the bottom edge.
///
/// Each side is one cubic with horizontal tangents at both ends, so it leaves
/// the bar concave and rounds into the bottom convex.
///
/// Drawn across the full panel width because the flares paint outside the
/// body, so the panel must be wider than the body by a flare on each side.
/// bodyOffset keeps the body under its item when the panel is pushed inward
/// at a screen edge; each flare is clamped to its own side's room.
///
/// Coordinates are SwiftUI, y down, with the top edge on the bar's underside.
@Animatable
nonisolated struct NotchShape: InsettableShape {
    /// Width of the descending body.
    @AnimatableIgnored var bodyWidth: CGFloat
    /// Signed horizontal displacement of the body from the panel's centre.
    @AnimatableIgnored var bodyOffset: CGFloat
    /// How far the body descends, measured from the bar's underside.
    var bodyHeight: CGFloat
    /// Base radius of the flare where the sides leave the bar's underside.
    /// The drawn flare is wider (see flareMultiplier); this is the unit of the
    /// panel's slack metrics.
    @AnimatableIgnored var shoulderRadius: CGFloat
    /// Inset where the side curves meet the flat bottom edge.
    @AnimatableIgnored var bottomRadius: CGFloat
    @AnimatableIgnored private var insetAmount: CGFloat = 0

    /// Flare reach relative to shoulderRadius. Above 1 so the sides taper out
    /// instead of turning a tight corner.
    private static let flareMultiplier: CGFloat = 2.4

    init(
        bodyWidth: CGFloat,
        bodyOffset: CGFloat,
        bodyHeight: CGFloat,
        shoulderRadius: CGFloat,
        bottomRadius: CGFloat
    ) {
        self.bodyWidth = bodyWidth
        self.bodyOffset = bodyOffset
        self.bodyHeight = bodyHeight
        self.shoulderRadius = shoulderRadius
        self.bottomRadius = bottomRadius
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount = amount
        return copy
    }

    func path(in rect0: CGRect) -> Path {
        let rect = rect0.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()

        let height = min(max(bodyHeight, 0), rect.height)

        // Below a hairline the fill reads as a smudge, not as nothing.
        guard height > 0.5 else {
            return path
        }

        let bodyMinX = rect.midX + bodyOffset - bodyWidth / 2
        let bodyMaxX = rect.midX + bodyOffset + bodyWidth / 2
        let bodyMaxY = rect.minY + height

        // Flares collapse for bodies still growing in and for sides pushed
        // against the panel edge.
        let desiredFlare = shoulderRadius * Self.flareMultiplier
        let flareLeft = min(desiredFlare, bodyMinX - rect.minX, height * 1.5)
        let flareRight = min(desiredFlare, rect.maxX - bodyMaxX, height * 1.5)

        let bottom = min(bottomRadius, bodyWidth / 2, height / 2)

        // Top edge spans only the body and flares; any wider and a stroked
        // border draws a hairline across the whole panel.
        path.move(to: CGPoint(x: bodyMinX - flareLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: bodyMaxX + flareRight, y: rect.minY))
        // Right side: control points on the body's top and bottom corners give
        // horizontal tangents at both ends.
        path.addCurve(
            to: CGPoint(x: bodyMaxX - bottom, y: bodyMaxY),
            control1: CGPoint(x: bodyMaxX, y: rect.minY),
            control2: CGPoint(x: bodyMaxX, y: bodyMaxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + bottom, y: bodyMaxY))
        // Left side, the mirrored S-curve back up into the bar.
        path.addCurve(
            to: CGPoint(x: bodyMinX - flareLeft, y: rect.minY),
            control1: CGPoint(x: bodyMinX, y: bodyMaxY),
            control2: CGPoint(x: bodyMinX, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
