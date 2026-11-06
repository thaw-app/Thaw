//
//  AXCropRules+Geometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

nonisolated extension AXCropRules {
    /// Splits candidates into those worth a screenshot and those whose bounds prove the prior image wrong.
    /// Parked or overlapping frames are in neither: they cannot identify the item's pixels, but say nothing against its glyph.
    static func eligibleCandidates(
        _ candidates: [(item: MenuBarItem, bounds: CGRect)],
        band: (frame: CGRect, menuMaxX: CGFloat?),
        overflowBounds: [CGRect],
        screens: [CGRect]
    ) -> (eligible: [(item: MenuBarItem, bounds: CGRect)], implausible: [MenuBarItem]) {
        let peers = candidates.map(\.item)
        var implausible = [MenuBarItem]()
        let eligible = candidates.filter { item, bounds in
            if hasUnusableCaptureGeometry(item, among: peers, screens: screens) {
                diagLog.debug("axBoundsCapture: \(item.logString) frame is parked or phantom; keeping its prior capture")
                return false
            }
            let overlapsOverflow = isContaminatedByNativeOverflow(bounds, overflowBounds: overflowBounds)
            let plausible = isPlausibleItemCaptureBounds(bounds)
                && isInStatusItemCaptureBand(bounds: bounds, applicationMenuMaxX: band.menuMaxX)
                && !overlapsOverflow
            if !plausible {
                if overlapsOverflow {
                    diagLog.debug("axBoundsCapture: rejecting native-overflow-contaminated bounds for \(item.logString)")
                }
                implausible.append(item)
            }
            return plausible
        }
        return (eligible, implausible)
    }

    /// The identifier of a neighbour the glyph bounds swallow, such as a 195pt sound module over a 27pt item.
    /// Coverage and relative width only count together, since wide items and small reflow overlaps are benign.
    static func coveredIdentifier(
        _ bounds: CGRect,
        ownIdentifier: String,
        liveBounds: [String: CGRect],
        minimumCoverage: CGFloat = 0.9,
        minimumWidthRatio: CGFloat = 1.5
    ) -> String? {
        guard !bounds.isEmpty else { return nil }
        // Measured on x alone: every item shares the bar's height, so vertical
        // overlap is true of any two items and carries no information.
        return liveBounds
            .lazy
            .filter { $0.key != ownIdentifier && !$0.value.isEmpty }
            .first { other in
                // Near-total containment, and wider than the neighbour: a 14pt
                // item can cover another 14pt item without engulfing it.
                let overlap = min(bounds.maxX, other.value.maxX) - max(bounds.minX, other.value.minX)
                return overlap > 0
                    && overlap >= other.value.width * minimumCoverage
                    && bounds.width >= other.value.width * minimumWidthRatio
            }?
            .key
    }

    static func isContaminatedByNativeOverflow(
        _ bounds: CGRect,
        overflowBounds: [CGRect],
        minimumOverflowCoverage: CGFloat = nativeOverflowCoverageFraction
    ) -> Bool {
        overflowBounds.contains { overflow in
            let overlap = bounds.intersection(overflow).width
            return overlap >= overflow.width * minimumOverflowCoverage
        }
    }

    /// Whether bounds lie on a display's menu bar strip. With several displays, AX can
    /// describe a bar other than the one captured; an item there says nothing about its picture.
    static func liesOnAMenuBar(_ bounds: CGRect, barHeight: CGFloat, displayBounds: [CGRect]) -> Bool {
        displayBounds.contains { CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: barHeight).intersects(bounds) }
    }

    /// The share of an overflow control's width a crop must overlap to carry chevron pixels. Concealed items
    /// parked in stacks graze the chevron, and a one-point graze is not contamination.
    static let nativeOverflowCoverageFraction: CGFloat = 0.5

    /// Whether the item's reported frame holds someone else's pixels: another on-band item's (hasPhantomFrame)
    /// or a spot parked off the band. Such items are skipped, not failed.
    static func hasUnusableCaptureGeometry(_ item: MenuBarItem, among peers: [MenuBarItem], screens: [CGRect]) -> Bool {
        item.hasPhantomFrame(among: peers) || item.isParkedOffMenuBarBand(among: peers, screens: screens)
    }

    /// Rejects hosting screenshots whose pixel size isn't windowFrame * scale; after a display-mode flip
    /// AppKit and ScreenCaptureKit can disagree on scale.
    static func isPlausibleHostingCapture(
        imageWidth: Int,
        imageHeight: Int,
        windowFrame: CGRect,
        scale: CGFloat,
        tolerance: CGFloat = 2
    ) -> Bool {
        guard scale > 0, scale.isFinite, windowFrame.width > 0, windowFrame.height > 0, windowFrame.width.isFinite, windowFrame.height.isFinite, imageWidth > 0, imageHeight > 0
        else {
            return false
        }

        let expectedWidth = windowFrame.width * scale
        let expectedHeight = windowFrame.height * scale
        return abs(CGFloat(imageWidth) - expectedWidth) <= tolerance
            && abs(CGFloat(imageHeight) - expectedHeight) <= tolerance
    }

    /// Rejects AX frames too wide to be a single status glyph, which would
    /// otherwise cache near-full-bar bitmaps.
    static func isPlausibleItemCaptureBounds(
        _ bounds: CGRect,
        maxWidthPoints: CGFloat = 200
    ) -> Bool {
        guard !bounds.isNull, !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0
        else {
            return false
        }

        // A hard point cap: a fraction of the bar admits app-menu-wide frames.
        return bounds.width <= maxWidthPoints
    }

    /// Whether a finished crop still fits the item's own frame. Oversized pixels come
    /// from a stale rect or scale mismatch and would carry a neighbour's glyph.
    static func isCropWithinItemBounds(
        imageWidth: Int,
        imageHeight: Int,
        itemBounds: CGRect,
        scale: CGFloat,
        tolerancePoints: CGFloat = 2
    ) -> Bool {
        guard scale > 0, scale.isFinite, !itemBounds.isNull, !itemBounds.isEmpty, itemBounds.width > 0, itemBounds.height > 0
        else {
            return false
        }
        return CGFloat(imageWidth) / scale <= itemBounds.width + tolerancePoints
            && CGFloat(imageHeight) / scale <= itemBounds.height + tolerancePoints
    }

    /// Status-item glyphs live right of the application menu; a frame in the
    /// app-menu band would crop menu text into the glyph cache.
    static func isInStatusItemCaptureBand(
        bounds: CGRect,
        applicationMenuMaxX: CGFloat?,
        leadingTolerance: CGFloat = 2
    ) -> Bool {
        guard !bounds.isNull, !bounds.isEmpty else { return false }

        if let applicationMenuMaxX, applicationMenuMaxX.isFinite {
            return bounds.minX >= applicationMenuMaxX - leadingTolerance
        }

        // No percentage fallback: menu widths vary too much. Miss until AX
        // supplies the boundary.
        return false
    }

    static func hasStableCaptureBounds(
        before: CGRect,
        after: CGRect,
        tolerance: CGFloat = 1.0
    ) -> Bool {
        abs(before.minX - after.minX) <= tolerance
            && abs(before.minY - after.minY) <= tolerance
            && abs(before.width - after.width) <= tolerance
            && abs(before.height - after.height) <= tolerance
    }

    /// Whether a captured scale is one a display could actually have produced.
    static func isPlausibleCaptureScale(_ scale: CGFloat) -> Bool {
        guard scale.isFinite, scale > 0 else { return false }
        return [1.0, 2.0, 3.0].contains { abs(scale - $0) <= 0.02 }
    }

    /// Which window a crop was taken from. An enum so a typo can't skip the bar window's opaque-slab guard.
    enum CaptureSource: String {
        case hosting
        case barWindow = "bar-window"
        case displayStrip = "display-strip"
    }
}
