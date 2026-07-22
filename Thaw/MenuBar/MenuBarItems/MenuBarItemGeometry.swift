//
//  MenuBarItemGeometry.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Geometry thresholds for classifying menu bar items that macOS 27 parks
/// off the visible bar band (concealed items retain phantom AX frames far
/// below the bar, or the transient `x == -1` sentinel).
nonisolated enum MenuBarItemGeometry {
    /// Maximum mid-Y an item's bounds may have to count as "on the bar band".
    static let maxOnBarMidY: CGFloat = 80

    /// Maximum |midY − barMidY| distance from the resolved bar mid-line for
    /// an item to count as on-bar when a live bar reference exists.
    static let maxDistanceFromBarMidY: CGFloat = 48

    /// Transient AX sentinel X origin reported for items mid-conceal/reveal.
    static let transientSentinelX: CGFloat = -1
}
