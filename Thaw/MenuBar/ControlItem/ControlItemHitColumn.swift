//
//  ControlItemHitColumn.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Thaw's icon column from the screen top to the icon's bottom: on macOS 27 a
/// click on the top row, above the icon's frame, still goes to the icon.
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
