//
//  LayoutBarDropMarker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The line Layout draws where a dragged item or group will land.
nonisolated enum LayoutBarDropMarker {
    static let width: CGFloat = 2
    static let verticalInset: CGFloat = 2

    /// A dragged item holds its slot open as an empty gap; the marker sits in the middle of it.
    static func x(inGap frames: [CGRect]) -> CGFloat? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }.midX
    }

    /// The slot a group dropped at x is inserted at: before the nearest frame, or after it
    /// when x is past its middle. The same rule the drop itself applies.
    static func insertionIndex(forX x: CGFloat, among frames: [CGRect]) -> Int {
        guard let nearest = frames.indices.min(by: { abs(frames[$0].midX - x) < abs(frames[$1].midX - x) }) else {
            return 0
        }
        return x > frames[nearest].midX ? nearest + 1 : nearest
    }

    /// A group dragged by its handle opens no gap, so the marker sits on the boundary it will be inserted at.
    static func x(insertingAt index: Int, among frames: [CGRect]) -> CGFloat? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if index <= 0 { return first.minX }
        if index >= frames.count { return last.maxX }
        return (frames[index - 1].maxX + frames[index].minX) / 2
    }

    /// The marker's rect, kept inside bounds so a slot at either end still shows a whole line.
    static func rect(atX x: CGFloat, in bounds: CGRect) -> CGRect {
        let centre = min(max(x, bounds.minX + width / 2), bounds.maxX - width / 2)
        return CGRect(
            x: centre - width / 2,
            y: bounds.minY + verticalInset,
            width: width,
            height: bounds.height - verticalInset * 2
        )
    }

    @MainActor
    static func draw(atX x: CGFloat, in bounds: CGRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect(atX: x, in: bounds), xRadius: width / 2, yRadius: width / 2).fill()
    }
}
