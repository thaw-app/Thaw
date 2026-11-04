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
    /// The identifiers among candidates that belong to a dropped item's app, sit outside target and
    /// aren't on the bar. Candidates may repeat; a recorded item with no assignment resolves through sectionOf.
    static func identifiers(
        following items: [MenuBarItem],
        to target: MenuBarSectionName,
        candidates: [String],
        sectionOf: (String) -> MenuBarSectionName,
        liveIdentifiers: Set<String>
    ) -> [String] {
        let prefixes = Set(items.filter { MenuBarItemGrouping.isGroupable($0.tag) }.map { "\($0.tag.namespace):" })
        guard !prefixes.isEmpty else { return [] }
        return Set(candidates)
            .filter { identifier in
                !liveIdentifiers.contains(identifier)
                    && prefixes.contains { identifier.hasPrefix($0) }
                    && sectionOf(identifier) != target
            }
            .sorted()
    }

    /// Moves the dropped items' absent siblings to target through controller, reading its
    /// assignments and recorded orders as candidates. Returns the identifiers it moved.
    @MainActor
    static func carry(
        _ items: [MenuBarItem],
        to target: MenuBarSectionName,
        in controller: any MenuBarSectionControlling,
        liveIdentifiers: Set<String>
    ) -> [String] {
        let siblings = identifiers(
            following: items,
            to: target,
            candidates: Array(controller.sectionAssignment.keys) + controller.sectionItemOrder.values.joined(),
            sectionOf: controller.section(for:),
            liveIdentifiers: liveIdentifiers
        )
        for identifier in siblings {
            controller.setSection(target, identifier: identifier)
        }
        return siblings
    }
}
