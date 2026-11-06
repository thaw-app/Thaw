//
//  MenuBarTooltipGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// The tooltip target and anchor are the same drawn seat that receives clicks.
nonisolated enum MenuBarTooltipGeometry {
    static func target(
        at pointer: CGPoint,
        entries: [(windowID: CGWindowID, bounds: CGRect)],
        destinationDisplay: CGRect?,
        displayBounds: [CGRect],
        laneMinX: CGFloat?
    ) -> (windowID: CGWindowID, bounds: CGRect)? {
        for entry in entries {
            guard let drawn = MirroredBarGeometry.drawnFrame(
                entry.bounds, on: destinationDisplay, displayBounds: displayBounds, laneMinX: laneMinX
            ), drawn.contains(pointer) else { continue }
            return (entry.windowID, drawn)
        }
        return nil
    }
}
