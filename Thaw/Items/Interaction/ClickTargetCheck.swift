//
//  ClickTargetCheck.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Whether a freshly read frame is safe to click: mid-reflow a re-read can return a parked or phantom
/// frame, and clicking it hits whatever sits there.
nonisolated enum ClickTargetCheck {
    enum Rejection: String {
        case empty
        /// The leading-edge sentinel macOS 27 reports for a parked item.
        case parked
        /// Below the bar's band, where macOS 27 parks items during a reflow.
        case offBar
        /// Wider than half the bar, so it is a host window spanning the bar rather than a status item.
        /// Items with text can be far wider than an icon, so the limit follows the bar, not an icon's size.
        case tooWide
    }

    /// The width of the bar bounds sits on: the widest display its centre falls on, or the widest
    /// display when it falls on none. Zero with no display.
    static func barWidth(for bounds: CGRect, displays: [CGRect]) -> CGFloat {
        let under = displays.filter { $0.minX <= bounds.midX && bounds.midX < $0.maxX }
        return (under.isEmpty ? displays : under).map(\.width).max() ?? 0
    }

    @MainActor
    static func barWidth(for bounds: CGRect) -> CGFloat {
        barWidth(for: bounds, displays: NSScreen.screens.map(\.frame))
    }

    /// A pointer on another bar selects its mirrored copy; desktop activation keeps the reported seat.
    static func clickPoint(
        for bounds: CGRect,
        pointer: CGPoint,
        display: CGRect,
        menuBarHeight: CGFloat,
        displays: [CGRect]
    ) -> CGPoint {
        guard MenuBarItemGeometry.contains(pointer, inTopBandOf: display, height: menuBarHeight) else {
            return bounds.center
        }
        return MirroredBarGeometry.frame(bounds, on: display, displayBounds: displays).center
    }

    /// - Parameter barWidth: The width of the bar the frame sits on; zero skips the width check.
    static func rejection(for bounds: CGRect, barWidth: CGFloat, displays: [CGRect]) -> Rejection? {
        guard !bounds.isNull, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0
        else { return .empty }
        if bounds.origin.x == -1 { return .parked }
        if MenuBarItemGeometry.barScreen(holding: bounds, among: displays) == nil {
            return .offBar
        }
        if barWidth > 0, bounds.width > barWidth / 2 { return .tooWide }
        return nil
    }
}
