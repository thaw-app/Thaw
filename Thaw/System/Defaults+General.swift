//
//  Defaults+General.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension Defaults.DefaultValue {
    static let showThawIcon = true
    static let thawIcon = ControlItemImageSet.defaultThawIcon
    static let customThawIconIsTemplate = false
    static let simpleMode = false
    static let showSettingDescriptions = true
    static let simpleModeShowsPreview = true
    /// On, as Thaw 3 has always behaved: Settings makes Thaw a regular app.
    static let showDockIconWithSettings = true
}
