//
//  MenuBarItemGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Geometry thresholds for classifying menu bar items that macOS 27 parks
/// off the visible bar band (concealed items retain phantom AX frames far
/// below the bar, or the transient x == -1 sentinel).
nonisolated enum MenuBarItemGeometry {
    /// Maximum mid-Y an item's bounds may have to count as "on the bar band".
    static let maxOnBarMidY: CGFloat = 80

    /// Maximum |midY − barMidY| distance from the resolved bar mid-line for
    /// an item to count as on-bar when a live bar reference exists.
    static let maxDistanceFromBarMidY: CGFloat = 48

    /// Transient AX sentinel X origin reported for items mid-conceal/reveal.
    static let transientSentinelX: CGFloat = -1

    /// Two on-band frames whose minX differ by less than this share a seat.
    static let phantomFrameXTolerance: CGFloat = 0.5

    /// The fraction of the narrower frame two on-band items may overlap
    /// horizontally before one of them is a phantom.
    static let phantomFrameOverlapFraction: CGFloat = 0.5

    /// An overlap narrower than this is sub-point rounding on a scaled
    /// display, never a shared seat.
    static let phantomFrameMinimumOverlap: CGFloat = 4

    /// A peer narrower than this is a collapsed divider or a concealed
    /// item's sliver, not a glyph anything could be drawn under.
    static let phantomFramePeerMinimumWidth: CGFloat = 8

    /// The screen, of screenFrames in CG-global points, whose menu bar holds
    /// frame, or nil when frame is on no bar.
    ///
    /// Rejects the x == -1 sentinel: macOS parks items there with isOnScreen
    /// still true and a Y on no screen or on the wrong display. The mid-line
    /// check is per screen so a bar on a display below the main one counts.
    static func barScreen(holding frame: CGRect, among screenFrames: [CGRect]) -> CGRect? {
        guard frame.width > 0, frame.origin.x != transientSentinelX else { return nil }
        return screenFrames.first { screen in
            screen.contains(frame.origin) && frame.midY - screen.minY <= maxOnBarMidY
        }
    }
}

nonisolated extension MenuBarItem {
    /// Whether this item's AX frame is a phantom: a seat another on-band item
    /// already occupies.
    ///
    /// An evicted item can keep its last AX frame while something else is drawn
    /// there, and a drag aimed at it grabs the wrong item. Detected as a shared
    /// minX or large overlap; system clones and slivers are not peers.
    func hasPhantomFrame(among peers: [MenuBarItem]) -> Bool {
        guard !isSystemClone, bounds.width > 0, bounds.height > 0 else { return false }
        return peers.contains { peer in
            guard peer.windowID != windowID,
                  !peer.isSystemClone,
                  peer.bounds.width >= MenuBarItemGeometry.phantomFramePeerMinimumWidth,
                  peer.bounds.height > 0,
                  abs(peer.bounds.midY - bounds.midY) <= MenuBarItemGeometry.maxDistanceFromBarMidY
            else {
                return false
            }
            if abs(peer.bounds.minX - bounds.minX) < MenuBarItemGeometry.phantomFrameXTolerance {
                return true
            }
            let overlap = bounds.intersection(peer.bounds).width
            return overlap >= MenuBarItemGeometry.phantomFrameMinimumOverlap &&
                overlap > min(bounds.width, peer.bounds.width) * MenuBarItemGeometry.phantomFrameOverlapFraction
        }
    }
}
