//
//  MenuBarDisplayChangeEffects+Profile.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarDisplayChangeEffects {
    /// Runs after startSettle, so the apply's layout waits for the settle and the settle's tail finds
    /// the apply pending instead of applying the profile a second time.
    func resolveDisplayProfile() async {
        displayProfileSwitch.settle(
            displayUUID: Bridging.getActiveMenuBarDisplayUUID(),
            activeSpaceKey: SpaceInfo.activeSpace().persistentKey,
            on: profiles
        )
    }
}
