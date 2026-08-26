//
//  SpaceInfo.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Information for a desktop space.
struct SpaceInfo: Hashable {
    /// The space's identifier.
    let spaceID: CGSSpaceID

    /// A Boolean value that indicates whether the space is fullscreen.
    let isFullscreen: Bool

    /// Creates a space with the given identifier.
    ///
    /// - Parameter spaceID: An identifier for a space.
    init(spaceID: CGSSpaceID) {
        self.spaceID = spaceID
        self.isFullscreen = Bridging.isSpaceFullscreen(spaceID)
    }

    /// The space as the window server currently describes it, or `nil` if
    /// it has not been published in the managed-display list yet.
    ///
    /// Looked up on demand rather than stored, because resolving it walks
    /// the window server's full managed-display list.
    var managedSpace: Bridging.ManagedSpace? {
        Bridging.getManagedSpaces().first { $0.spaceID == spaceID }
    }

    /// A reboot-stable key for the space, suitable for persisting.
    ///
    /// Unlike ``spaceID``, this survives logout.
    var persistentKey: String? {
        managedSpace?.persistentKey
    }

    /// A human-readable label for the space, matching how Mission Control
    /// numbers desktops. Spaces carry no user-facing name of their own.
    ///
    /// Resolved once and stored alongside the association rather than
    /// recomputed, because the ordinal moves when the user reorders their
    /// desktops and a label that silently renumbered itself would be worse
    /// than one that is merely out of date.
    var localizedLabel: String {
        guard let managedSpace else {
            return String(localized: "Current Space", comment: "Label for a Space that has not been published by the window server yet.")
        }
        return isFullscreen
            ? String(
                localized: "Full Screen Space \(managedSpace.ordinal)",
                comment: "Label for a fullscreen Space, numbered as Mission Control numbers it."
            )
            : String(
                localized: "Desktop \(managedSpace.ordinal)",
                comment: "Label for a desktop Space, numbered as Mission Control numbers it."
            )
    }

    /// Returns the active space.
    static func activeSpace() -> SpaceInfo {
        SpaceInfo(spaceID: Bridging.getActiveSpaceID())
    }

    /// Returns the current space on the given display.
    ///
    /// - Parameter displayID: An identifier for a display.
    static func currentSpace(for displayID: CGDirectDisplayID) -> SpaceInfo? {
        guard let spaceID = Bridging.getCurrentSpaceID(for: displayID) else {
            return nil
        }
        return SpaceInfo(spaceID: spaceID)
    }
}
