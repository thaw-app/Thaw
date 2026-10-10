//
//  MenuBarItemGrouping.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Groups menu bar items that belong to the same application so the layout UI
/// can present them as a movable cluster.
///
/// A group is two or more groupable items in a section sharing a bundle
/// namespace, adjacent or not. Moving the group gathers scattered members.
///
/// Pure so the rules are testable without a live menu bar.
nonisolated enum MenuBarItemGrouping {
    /// A set of same-bundle items within an ordered sequence.
    struct Group: Equatable, Sendable {
        let namespace: MenuBarItemTag.Namespace
        /// Ascending, not necessarily contiguous.
        let memberIndices: [Int]

        init(namespace: MenuBarItemTag.Namespace, memberIndices: [Int]) {
            self.namespace = namespace
            self.memberIndices = memberIndices
        }

        var count: Int {
            memberIndices.count
        }

        /// May enclose non-members when the group is not contiguous.
        var range: Range<Int> {
            guard let first = memberIndices.first, let last = memberIndices.last else {
                return 0 ..< 0
            }
            return first ..< (last + 1)
        }
    }

    /// Whether an item is eligible to participate in bundle grouping.
    ///
    /// Only third-party apps group. Excluded:
    /// - System items and the menu bar host namespace, which would collapse
    ///   every Apple module into one group.
    /// - Thaw's own control items.
    /// - Fixed layout anchors and any non-movable item.
    /// - Items whose namespace is not a bundle string (UUID / null clones).
    static func isGroupable(_ tag: MenuBarItemTag) -> Bool {
        guard tag.namespace.isString else { return false }
        guard !tag.isSystemItem else { return false }
        guard tag.namespace != .thaw else { return false }
        return tag.isMovable
    }

    /// Detects the bundle groups (two or more same-bundle groupable items) in a
    /// tag sequence, in left-to-right order of each bundle's first member.
    ///
    /// Items need not be adjacent, and a bundle never splits into two groups.
    static func groups(in tags: [MenuBarItemTag]) -> [Group] {
        var indicesByNamespace = [MenuBarItemTag.Namespace: [Int]]()
        var firstSeen = [MenuBarItemTag.Namespace: Int]()

        for (index, tag) in tags.enumerated() {
            guard isGroupable(tag) else { continue }
            indicesByNamespace[tag.namespace, default: []].append(index)
            if firstSeen[tag.namespace] == nil {
                firstSeen[tag.namespace] = index
            }
        }

        return indicesByNamespace
            .filter { $0.value.count >= 2 }
            .sorted { (firstSeen[$0.key] ?? 0) < (firstSeen[$1.key] ?? 0) }
            .map { Group(namespace: $0.key, memberIndices: $0.value) }
    }

    static func group(containing index: Int, in tags: [MenuBarItemTag]) -> Group? {
        groups(in: tags).first { $0.memberIndices.contains(index) }
    }
}
