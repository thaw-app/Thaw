//
//  DisplayArrangement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Which displays are connected, where each one sits, and which one is main.
/// A swapped display, a new arrangement or another main display moves every bar without changing the count.
nonisolated struct DisplayArrangement: Equatable {
    /// Each display's frame in global coordinates, by display ID.
    let frames: [CGDirectDisplayID: CGRect]
    let mainDisplayID: CGDirectDisplayID?

    /// The displays Thaw manages right now.
    @MainActor
    static var current: Self {
        let screens = NSScreen.managedScreens
        return Self(
            frames: Dictionary(screens.map { ($0.displayID, CGDisplayBounds($0.displayID)) }) { first, _ in first },
            mainDisplayID: screens.isEmpty ? nil : CGMainDisplayID()
        )
    }
}
