//
//  ControlItemHitColumn.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Where a click counts as a click on Thaw's icon: its column from the top
/// of its screen down to the icon's bottom edge. On macOS 27 the icon's frame
/// starts a few points below the top of the screen, yet macOS still sends a
/// click at the very top to the icon, so testing the frame alone misses it.
nonisolated enum ControlItemHitColumn {
    /// In AppKit coordinates, where y grows upward and screenMaxY is the top
    /// of the icon's screen. One point more, since CGRect.contains leaves out
    /// its max edge and the pointer can rest on the topmost row.
    static func appKit(_ frame: CGRect, screenMaxY: CGFloat) -> CGRect {
        let top = max(frame.maxY, screenMaxY) + 1
        return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: top - frame.minY)
    }

    /// In Quartz coordinates, where y grows downward and screenMinY is the
    /// top of the icon's display.
    static func quartz(_ frame: CGRect, screenMinY: CGFloat) -> CGRect {
        let top = min(frame.minY, screenMinY)
        return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.maxY - top)
    }
}
