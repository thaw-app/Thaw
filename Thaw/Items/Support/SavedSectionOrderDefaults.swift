//
//  SavedSectionOrderDefaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Where the saved section order is kept in defaults: identifiers by section name.
nonisolated enum SavedSectionOrderDefaults {
    static let key = "MenuBarItemManager.savedSectionOrder"

    static func read(from defaults: UserDefaults = .standard) -> [String: [String]] {
        defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
}
