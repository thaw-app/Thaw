//
//  OverlaySpaceLookup.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Which Space a screen shows, as the appearance overlay needs it to pick its level and visibility.
@MainActor
enum OverlaySpaceLookup {
    static func isFullscreenSpace(on screen: NSScreen) -> Bool {
        guard let spaceID = currentSpaceID(on: screen) else { return false }
        return Bridging.isSpaceFullscreen(spaceID)
    }

    private static func currentSpaceID(on screen: NSScreen) -> CGSSpaceID? {
        resolvedSpaceID(
            displaySpace: Bridging.getCurrentSpaceID(for: screen.displayID),
            activeSpace: Bridging.getActiveSpaceID(),
            ownsActiveMenuBar: screen == NSScreen.main
        )
    }

    /// The per-display query can stop answering; the screen with the active menu bar then shows the active Space.
    static nonisolated func resolvedSpaceID(
        displaySpace: CGSSpaceID?,
        activeSpace: CGSSpaceID,
        ownsActiveMenuBar: Bool
    ) -> CGSSpaceID? {
        if let displaySpace, displaySpace != 0 {
            return displaySpace
        }
        guard ownsActiveMenuBar, activeSpace != 0 else { return nil }
        return activeSpace
    }
}
