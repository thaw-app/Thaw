//
//  BarAxis.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Supplies CG-global display bounds for shared-axis ordering without a main-actor hop.
public nonisolated enum BarAxis {
    /// Returns active displays' bounds, or an empty array when enumeration fails.
    public static func liveDisplayBounds() -> [CGRect] {
        Bridging.activeDisplayIDs().map { CGDisplayBounds($0) }
    }
}
