//
//  SyntheticDragNotchGuard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Decides whether a synthetic drag would grab or drop under a display's notch.
///
/// The notch hides what sits beneath it but still reports on-band geometry, so
/// such a drag moves an item the user cannot see. Refusing it turns that into
/// a failed move the caller can report instead of a layout that looks unchanged.
///
/// Inputs must share one coordinate space; the engine passes top-left
/// CG-global points.
nonisolated enum SyntheticDragNotchGuard {
    /// The first endpoint a notch covers, grab before drop, with that notch.
    /// Containment is half-open like CGRect.contains: a notch's trailing edge is
    /// the first visible column beside it and is allowed. Degenerate rectangles,
    /// such as auxiliary areas with no gap between them, never cover anything.
    static func coveredEndpoint(
        start: CGPoint,
        end: CGPoint,
        notchRects: [CGRect]
    ) -> (point: CGPoint, notch: CGRect)? {
        for point in [start, end] {
            if let notch = notchRects.first(where: { !$0.isNull && !$0.isEmpty && $0.contains(point) }) {
                return (point, notch)
            }
        }
        return nil
    }
}

extension SyntheticDragNotchGuard {
    /// Every display's notch in top-left CG-global coordinates. Read live from
    /// frameOfNotch because it honors debugSimulateNotch and the kit's
    /// MenuBarNotchGeometry snapshot does not.
    @MainActor
    static func liveNotchRects() -> [CGRect] {
        let screens = NSScreen.screens
        guard let primaryMaxY = screens.first?.frame.maxY else { return [] }
        return screens.compactMap { screen in
            screen.frameOfNotch.map { notch in
                CGRect(x: notch.minX, y: primaryMaxY - notch.maxY, width: notch.width, height: notch.height)
            }
        }
    }
}
