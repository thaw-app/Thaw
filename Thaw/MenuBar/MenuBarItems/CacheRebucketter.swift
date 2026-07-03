//
//  CacheRebucketter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Reconstructs Visible/Hidden/Always-Hidden cache buckets from assertion-backed
/// assignments. AX enumeration only returns live items and cannot classify the
/// zero-width section dividers on macOS 27.
enum CacheRebucketter {
    @MainActor
    static func rebucket(
        _ input: MenuBarItemManager.ItemCache,
        sectionFor: (MenuBarItem) -> MenuBarSection.Name,
        sectionAssignment: [String: MenuBarSection.Name],
        allowsAlwaysHidden: Bool,
        retainedSnapshotFor: (String) -> MenuBarItem?,
        orderedItems: ([MenuBarItem], MenuBarSection.Name) -> [MenuBarItem]
    ) -> MenuBarItemManager.ItemCache {
        var cache = input
        var visible = [MenuBarItem]()
        var hidden = [MenuBarItem]()
        var alwaysHidden = [MenuBarItem]()

        for item in cache[.visible] {
            guard !item.isControlItem else {
                visible.append(item)
                continue
            }
            switch sectionFor(item) {
            case .visible:
                visible.append(item)
            case .hidden:
                hidden.append(item)
            case .alwaysHidden:
                if allowsAlwaysHidden {
                    alwaysHidden.append(item)
                } else {
                    hidden.append(item)
                }
            }
        }
        let liveIdentifiers = Set(cache[.visible].map(\.uniqueIdentifier))

        cache[.visible] = visible
        cache[.hidden] = hidden + retainedCachedItems(
            cache[.hidden],
            replacingLiveIdentifiers: liveIdentifiers
        )
        cache[.alwaysHidden] = alwaysHidden + retainedCachedItems(
            cache[.alwaysHidden],
            replacingLiveIdentifiers: liveIdentifiers
        )

        let cachedIdentifiers = Set(
            MenuBarSection.Name.allCases.flatMap { cache[$0].map(\.uniqueIdentifier) }
        )
        for (identifier, section) in sectionAssignment where !cachedIdentifiers.contains(identifier) {
            guard let snapshot = retainedSnapshotFor(identifier) else { continue }
            let target: MenuBarSection.Name = section == .alwaysHidden && allowsAlwaysHidden
                ? .alwaysHidden
                : .hidden
            cache[target].append(snapshot)
        }

        for section in MenuBarSection.Name.allCases {
            cache[section] = orderedItems(cache[section], section)
        }
        return cache
    }

    static func retainedCachedItems(
        _ items: [MenuBarItem],
        replacingLiveIdentifiers liveIdentifiers: Set<String>
    ) -> [MenuBarItem] {
        items.filter { !liveIdentifiers.contains($0.uniqueIdentifier) }
    }
}
