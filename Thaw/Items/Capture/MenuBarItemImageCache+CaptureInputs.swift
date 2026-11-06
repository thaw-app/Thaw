//
//  MenuBarItemImageCache+CaptureInputs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    /// The display a grouped reveal captures from, and the one its item cache
    /// was on when the reveal was chosen.
    nonisolated struct RevealCaptureTarget {
        let displayID: CGDirectDisplayID
        let admittedDisplayID: CGDirectDisplayID?
        let scale: CGFloat
    }
}
