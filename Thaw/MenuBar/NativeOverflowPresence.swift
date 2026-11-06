//
//  NativeOverflowPresence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Observation

/// The displays where macOS's own overflow arrow is showing, copied from the section engine,
/// which doesn't publish it, each time the engine updates its control items.
@MainActor
@Observable
final class NativeOverflowPresence {
    private(set) var displayIDs: Set<CGDirectDisplayID> = []

    /// Rereads the engine's answer for every connected display.
    func refresh(displays: Set<CGDirectDisplayID>, isActive: (CGDirectDisplayID) -> Bool) {
        let active = displays.filter(isActive)
        // Observation notifies on every write, so an equal set is not written back.
        if active != displayIDs {
            displayIDs = active
        }
    }

    /// Whether macOS's overflow is showing on displayID. False when there is no display.
    func isPresent(on displayID: CGDirectDisplayID?) -> Bool {
        displayID.map(displayIDs.contains) ?? false
    }
}
