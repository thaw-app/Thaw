//
//  DrawnOnlyItems+SavedIdentity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

nonisolated extension DrawnOnlyItems {
    /// The identity title of each app that has exactly one identity in the saved section order, by bundle ID.
    ///
    /// The saved order survives a relaunch and the section controller derives its assignment from it, so an
    /// item with this title lands in the saved section. An app with several saved identities is left out,
    /// since nothing says which one a lone drawn entry is, and so is one whose only identity has an instance.
    ///
    /// - Parameter order: Identifiers by section, each `bundleID:title` with an optional `:instance`.
    static func savedIdentityTitles(in order: [String: [String]]) -> [String: String] {
        var titles: [String: Set<String>] = [:]
        for identifier in order.values.joined().map(MenuBarItemTag.canonicalPersistentIdentifier) {
            // A bundle ID never contains a colon, so the first one ends it.
            guard let separator = identifier.firstIndex(of: ":") else { continue }
            let title = identifier[identifier.index(after: separator)...]
            guard !title.isEmpty else { continue }
            titles[String(identifier[..<separator]), default: []].insert(String(title))
        }
        // A lone identity ending in :<number> may name a second instance, whose window ID and store key a
        // single stand-in cannot give, so it is left out too.
        return titles.compactMapValues { candidates in
            guard candidates.count == 1, let title = candidates.first, title.wholeMatch(of: /.+:\d+/) == nil else { return nil }
            return title
        }
    }
}

nonisolated extension DrawnOnlyInventory {
    /// The section order the section controller persists. Read on each pass, so the last saved edit counts.
    static func persistedSectionOrder() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: "MenuBarItemManager.savedSectionOrder") as? [String: [String]] ?? [:]
    }
}
