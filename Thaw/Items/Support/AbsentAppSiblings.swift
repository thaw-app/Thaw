//
//  AbsentAppSiblings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Items of a dropped item's app that sit in another section while they aren't on the bar.
///
/// Native hiding keeps an app on the bar while any of its items is placed in Visible,
/// drawn or not. Layout shows only drawn items, so such an item can't be dragged back,
/// and moving the app's drawn item has to bring it along.
nonisolated enum AbsentAppSiblings {
    static func identifiers(
        following items: [MenuBarItem],
        to target: MenuBarSectionName,
        assignment: [String: MenuBarSectionName],
        liveIdentifiers: Set<String>
    ) -> [String] {
        let prefixes = Set(items.filter { MenuBarItemGrouping.isGroupable($0.tag) }.map { "\($0.tag.namespace):" })
        guard !prefixes.isEmpty else { return [] }
        return assignment
            .filter { identifier, section in
                section != target
                    && !liveIdentifiers.contains(identifier)
                    && prefixes.contains { identifier.hasPrefix($0) }
            }
            .map(\.key)
            .sorted()
    }
}
