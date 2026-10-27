//
//  ItemHintGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// The drawn seat used both to select hint targets and place their badges.
nonisolated enum ItemHintGeometry {
    static func frame(
        _ bounds: CGRect,
        on display: CGRect,
        displays: [CGRect],
        barHeight: CGFloat,
        laneMinX: CGFloat?
    ) -> CGRect? {
        guard MenuBarItemGeometry.barScreen(holding: bounds, among: displays) != nil,
              let drawn = MirroredBarGeometry.drawnFrame(
                  bounds, on: display, displayBounds: displays, laneMinX: laneMinX
              ), MenuBarItemGeometry.contains(drawn.center, inTopBandOf: display, height: barHeight)
        else { return nil }
        return drawn
    }
}
