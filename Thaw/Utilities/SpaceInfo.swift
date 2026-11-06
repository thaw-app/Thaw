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

    static func activeSpace() -> SpaceInfo {
        SpaceInfo(spaceID: Bridging.getActiveSpaceID())
    }
}
