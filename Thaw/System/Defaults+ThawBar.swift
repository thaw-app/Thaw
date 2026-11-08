//
//  Defaults+ThawBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension Defaults.DefaultValue {
    static let lockThawBarPosition = true
    static let openHiddenItemsInMenuBar = false
    static let useThawBar = false
    static let useThawBarOnlyOnNotchedDisplay = false
    static let thawBarLocation: ThawBarLocation = .dynamic
    static let thawBarLocationOnHotkey = false
    /// On, as Thaw 2 shipped and Thaw 3 has always behaved: items notch overflow
    /// pushed out can't show inline, so the Thaw Bar shows them.
    static let useThawBarOnNotchOverflow = true
}
