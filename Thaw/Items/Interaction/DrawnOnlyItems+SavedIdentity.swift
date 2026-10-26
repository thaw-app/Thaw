//
//  DrawnOnlyItems+SavedIdentity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

nonisolated extension DrawnOnlyItems {
    /// The title of each app's one identity in the saved section order, by bundle ID, so a drawn item lands
    /// in its saved section. Apps with several identities, or one with an instance, are left out.
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
        // A trailing :<number> may name a second instance, whose window ID and store key a stand-in cannot give.
        return titles.compactMapValues { candidates in
            guard candidates.count == 1, let title = candidates.first, title.wholeMatch(of: /.+:\d+/) == nil else { return nil }
            return title
        }
    }
}

nonisolated extension DrawnOnlyInventory {
    /// Read on each pass, so the last saved edit counts.
    static func persistedSectionOrder() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: "MenuBarItemManager.savedSectionOrder") as? [String: [String]] ?? [:]
    }
}
