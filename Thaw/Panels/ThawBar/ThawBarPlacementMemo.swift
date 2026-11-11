//
//  ThawBarPlacementMemo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The content size the Thaw Bar's panel was last fitted to, so a layout pass that changes nothing doesn't
/// refit it. AppKit sizes windows in whole points, so a half-point ideal size never equals the frame it produced.
nonisolated struct ThawBarContentFit: Equatable {
    private var ideal: CGSize?
    private var frameSize: CGSize?

    /// Whether the panel still has to take the content's ideal size.
    func needsResize(ideal: CGSize, frameSize: CGSize) -> Bool {
        if ideal == frameSize {
            return false
        }
        return ideal != self.ideal || frameSize != self.frameSize
    }

    /// Records the frame size the panel took once ideal was applied.
    mutating func noteResize(ideal: CGSize, frameSize: CGSize) {
        self.ideal = ideal
        self.frameSize = frameSize
    }
}

/// The clamped placement the Thaw Bar last logged, so each open reports a clamp once per
/// distinct value instead of once per placement.
nonisolated struct ThawBarClampReport {
    private var desiredX: CGFloat?
    private var clamped: CGFloat?
    private var opening: ContinuousClock.Instant?

    /// Whether clamping moved the bar more than a point and this open has not reported it yet.
    mutating func isNew(desiredX: CGFloat, clamped: CGFloat, since opening: ContinuousClock.Instant?) -> Bool {
        guard abs(clamped - desiredX) > 1 else { return false }
        if desiredX == self.desiredX, clamped == self.clamped, opening == self.opening {
            return false
        }
        (self.desiredX, self.clamped, self.opening) = (desiredX, clamped, opening)
        return true
    }
}
