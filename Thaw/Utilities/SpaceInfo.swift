//
//  SpaceInfo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Information for a desktop space.
struct SpaceInfo: Hashable {
    let spaceID: CGSSpaceID

    let isFullscreen: Bool

    init(spaceID: CGSSpaceID) {
        self.spaceID = spaceID
        self.isFullscreen = Bridging.isSpaceFullscreen(spaceID)
    }

    /// Nil until the window server publishes the space. Each read walks the
    /// full managed-display list.
    var managedSpace: Bridging.ManagedSpace? {
        Bridging.getManagedSpaces().first { $0.spaceID == spaceID }
    }

    /// A key that survives logout and reboot, unlike spaceID.
    var persistentKey: String? {
        managedSpace?.persistentKey
    }

    /// The desktop number Mission Control shows; spaces have no name of their own.
    /// Callers store it once, since a label that renumbers itself is worse than a stale one.
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

    static func activeSpace() -> SpaceInfo {
        SpaceInfo(spaceID: Bridging.getActiveSpaceID())
    }
}
