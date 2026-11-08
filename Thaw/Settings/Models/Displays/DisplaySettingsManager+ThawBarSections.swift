//
//  DisplaySettingsManager+ThawBarSections.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics

extension DisplaySettingsManager {
    /// Whether section opens in the Thaw Bar on displayID by that display's own choice.
    func useThawBar(for displayID: CGDirectDisplayID, section: MenuBarSection.Name) -> Bool {
        let configuration = configuration(for: displayID)
        return configuration.useThawBar || (section == .alwaysHidden && configuration.useThawBarForAlwaysHidden)
    }

    /// Sets the Always-Hidden-only choice for one display.
    func setUseThawBarForAlwaysHidden(_ value: Bool, forDisplayUUID uuid: String) {
        updateConfiguration(forDisplayUUID: uuid) { $0.withUseThawBarForAlwaysHidden(value) }
    }
}
