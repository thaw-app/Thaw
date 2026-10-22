//
//  NewIconSectionFollower.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation

/// Which new icons join their app's hidden ones, and where an app's first icon
/// goes. macOS 27 hides per app, so a new icon left in Visible would bring a
/// fully hidden app back onto the bar.
nonisolated struct NewIconArrivals {
    /// An app that rewrites an icon's title looks like a stream of new icons;
    /// past this many in one session it is left alone.
    static let placementsPerApp = 3

    private(set) var seen: Set<String>
    private var placed: [String: Int] = [:]

    init(seen: Set<String>) {
        self.seen = Set(seen.map(MenuBarItemTag.canonicalPersistentIdentifier))
    }

    /// One icon to place. isNewApp is true when its app had no icons before,
    /// so it also takes the New Items placeholder's position in the section.
    struct Placement: Equatable {
        let identifier: String
        let section: MenuBarSectionName
        let isNewApp: Bool
    }

    /// Placements for the unseen icons in current. An icon joins the hidden section
    /// all its app's other icons share; a new app's first icon goes to the New Items
    /// section unless that is Visible. Everything in current counts as seen afterwards.
    mutating func placements(
        current: [String],
        saved: [String],
        authored: (String) -> MenuBarSectionName,
        newItemsSection: MenuBarSectionName = .visible
    ) -> [Placement] {
        let current = MenuBarItemTag.canonicalPersistentIdentifiers(current)
        let arrivals = current.filter { !seen.contains($0) }
        guard !arrivals.isEmpty else { return [] }
        let known = Set(current).union(MenuBarItemTag.canonicalPersistentIdentifiers(saved)).subtracting(arrivals)
        seen.formUnion(arrivals)
        return arrivals.compactMap { arrival in
            guard let app = Self.app(of: arrival), !app.hasPrefix("com.apple.") else { return nil }
            let appIcons = known.filter { Self.app(of: $0) == app }
            // A new app's icon goes where Layout's New Items placeholder says. On macOS 27
            // the cache's own check for new items reads divider frames that are zero-width.
            let sections = appIcons.isEmpty ? [newItemsSection] : Set(appIcons.map(authored))
            guard sections.count == 1, let section = sections.first, section != .visible,
                  placed[app, default: 0] < Self.placementsPerApp
            else { return nil }
            placed[app, default: 0] += 1
            return Placement(identifier: arrival, section: section, isNewApp: appIcons.isEmpty)
        }
    }

    /// The section's order with identifier at index, the New Items placeholder's
    /// slot, and nowhere else. The index counts the order without identifier.
    static func order(placing identifier: String, in order: [String], at index: Int) -> [String] {
        let canonical = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        var others = order.filter { MenuBarItemTag.canonicalPersistentIdentifier($0) != canonical }
        others.insert(identifier, at: min(max(index, 0), others.count))
        return others
    }

    /// The bundle ID in front of an identifier's first colon.
    private static func app(of identifier: String) -> String? {
        identifier.firstIndex(of: ":").map { String(identifier[..<$0]) }
    }
}
