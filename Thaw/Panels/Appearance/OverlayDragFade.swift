//
//  OverlayDragFade.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import QuartzCore

/// How the overlay fades while a menu bar item is dragged, so the real bar shows as the drag starts.
nonisolated enum OverlayDragFade {
    /// Fading out starts fast and lands soft, so the bar is visible within the first frames of the drag.
    static var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    /// Out takes 0.15 s and back in 0.2 s, each scaled by the distance left, so a reversal mid-fade
    /// doesn't take the full time. Reduce Motion keeps the fade, which hides the bar's own colors, but caps it at 0.1 s.
    static func duration(from: Float, to: Float, reduceMotion: Bool) -> CFTimeInterval {
        let full: CFTimeInterval = to < from ? 0.15 : 0.2
        let capped = reduceMotion ? min(full, 0.1) : full
        return capped * CFTimeInterval(min(1, abs(to - from)))
    }
}
