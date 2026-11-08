//
//  Defaults+Search.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension Defaults.DefaultValue {
    static let rememberSearchQuery = false
    /// The bar under the search list with Settings, Remember last search and
    /// the Rename, Actions and Return hints.
    static let showSearchShortcutBar = true
    /// How the menu bar search panel opens. Stored as the case's raw
    /// value; the default is the behavior the panel shipped with.
    static let menuBarSearchPresentation = SearchPresentation.extended
}
