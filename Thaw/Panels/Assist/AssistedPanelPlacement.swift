//
//  AssistedPanelPlacement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Places the assisted palette at the pointer, so the user never travels to
/// reach it: centered horizontally, below the pointer, flipping above when
/// there is no room. Coordinates are AppKit global (origin bottom-left of
/// the primary display), like NSEvent.mouseLocation.
nonisolated enum AssistedPanelPlacement {
    /// Gap between the pointer and the panel, so the row under the cursor
    /// is never covered by the panel that lists it.
    static let pointerGap: CGFloat = 18

    static func frame(near pointer: CGPoint, in visibleFrame: CGRect, size: CGSize) -> CGRect {
        let x = (pointer.x - size.width / 2)
            .clamped(to: visibleFrame.minX ... (visibleFrame.maxX - size.width))

        // AppKit Y grows upward, so "below" the pointer is the smaller Y.
        let roomBelow = pointer.y - pointerGap - visibleFrame.minY
        let roomAbove = visibleFrame.maxY - (pointer.y + pointerGap)

        // Prefer below. If neither side fits, the roomier side wins and the
        // clamp covers as little of the pointer as it can.
        let originY: CGFloat = if roomBelow >= size.height || roomBelow >= roomAbove {
            (pointer.y - pointerGap - size.height)
                .clamped(to: visibleFrame.minY ... (visibleFrame.maxY - size.height))
        } else {
            (pointer.y + pointerGap)
                .clamped(to: visibleFrame.minY ... (visibleFrame.maxY - size.height))
        }
        return CGRect(x: x, y: originY, width: size.width, height: size.height)
    }
}
