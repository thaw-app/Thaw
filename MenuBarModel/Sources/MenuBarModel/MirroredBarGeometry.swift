//
//  MirroredBarGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// macOS 27 mirrors bars, but AX reports one display's frames; hit tests must rebase them for other displays.
/// Right-aligned items preserve distance from the trailing edge, not the leading coordinate.
public enum MirroredBarGeometry {
    /// Rebases to destinationDisplay, including the vertical offset for stacked displays.
    public static func rebasedFrame(
        _ frame: CGRect,
        from reportedDisplay: CGRect,
        to destinationDisplay: CGRect
    ) -> CGRect {
        guard reportedDisplay != destinationDisplay else { return frame }
        return frame.offsetBy(
            dx: destinationDisplay.maxX - reportedDisplay.maxX,
            dy: destinationDisplay.minY - reportedDisplay.minY
        )
    }

    /// Finds the source display by frame midpoint, then rebases to destinationDisplay.
    /// Frames already there or outside every known display remain unchanged.
    public static func frame(
        _ frame: CGRect,
        on destinationDisplay: CGRect?,
        displayBounds: [CGRect]
    ) -> CGRect {
        guard let destinationDisplay else { return frame }
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        guard let reportedDisplay = displayBounds.first(where: { $0.contains(midpoint) }) else {
            return frame
        }
        return rebasedFrame(frame, from: reportedDisplay, to: destinationDisplay)
    }

    /// frame(_:on:displayBounds:), or nil when the destination bar does not draw it.
    ///
    /// A bar lays its status items out from the trailing edge and draws only
    /// those that fit trailing laneMinX: its native overflow chevron's leading
    /// edge, or the notch's trailing edge when the chevron is unknown. An item
    /// starting before that sits in the chevron's menu, whatever frame it is
    /// reported with, and a frame mirrored from a bar with room to spare can
    /// land there too.
    public static func drawnFrame(
        _ frame: CGRect,
        on destinationDisplay: CGRect?,
        displayBounds: [CGRect],
        laneMinX: CGFloat?
    ) -> CGRect? {
        let drawn = self.frame(frame, on: destinationDisplay, displayBounds: displayBounds)
        guard let laneMinX, drawn.minX < laneMinX - laneTolerance else { return drawn }
        return nil
    }

    /// Points by which a drawn item may start before laneMinX, for AX rounding.
    static let laneTolerance: CGFloat = 1
}
