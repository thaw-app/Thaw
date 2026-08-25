//
//  MenuBarItemGrouping.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Groups menu bar items that belong to the same application so the layout UI
/// can present them as a movable cluster.
///
/// A *group* is the set of two or more groupable items in a section that share a
/// bundle namespace — **regardless of whether they are currently adjacent**. The
/// invariant the UI enforces is "every bundle with multiple items stays
/// together": the group handle gathers all members and moves them as one block,
/// so even items that start scattered are pulled into one contiguous cluster.
///
/// The type is intentionally pure and tag-driven so the grouping rules can be
/// unit-tested without a live menu bar, `AppState`, or AppKit view tree.
nonisolated enum MenuBarItemGrouping {
    /// A set of same-bundle items within an ordered sequence.
    struct Group: Equatable, Sendable {
        /// The shared namespace (bundle identity) of the members.
        let namespace: MenuBarItemTag.Namespace
        /// The indices of the members within the source array, ascending. The
        /// members are not necessarily contiguous.
        let memberIndices: [Int]

        init(namespace: MenuBarItemTag.Namespace, memberIndices: [Int]) {
            self.namespace = namespace
            self.memberIndices = memberIndices
        }

        /// The number of items in the group.
        var count: Int {
            memberIndices.count
        }

        /// The half-open span from the first to the last member. Used for
        /// drawing the cluster background and placing the group handle; may
        /// enclose non-member items when the group is not yet contiguous.
        var range: Range<Int> {
            guard let first = memberIndices.first, let last = memberIndices.last else {
                return 0 ..< 0
            }
            return first ..< (last + 1)
        }
    }

    /// Whether an item is eligible to participate in bundle grouping.
    ///
    /// Only genuine third-party applications group. Excluded:
    /// - System items and the menu-bar hosting namespace (Clock, Wi-Fi, …),
    ///   which would otherwise collapse every Apple module into one giant group.
    /// - Thaw's own control items.
    /// - Fixed layout anchors and any non-movable item.
    /// - Items whose namespace is not a bundle string (UUID / null clones).
    static func isGroupable(_ tag: MenuBarItemTag) -> Bool {
        guard tag.namespace.isString else { return false }
        guard !tag.isSystemItem else { return false }
        guard tag.namespace != .thaw else { return false }
        guard tag.namespace != .thaw else { return false }
        return tag.isMovable
    }

    /// Detects the bundle groups (two or more same-bundle groupable items) in a
    /// tag sequence, in left-to-right order of each bundle's first member.
    ///
    /// Membership is by bundle namespace only — items need **not** be adjacent.
    /// Every groupable item sharing a namespace with at least one sibling is a
    /// member of that bundle's single group, so a bundle's items are never split
    /// across two groups. Non-groupable items (system, Thaw, anchored,
    /// non-movable, non-string namespaces) are never members.
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

    /// The group containing the item at `index`, if that item is part of one.
    static func group(containing index: Int, in tags: [MenuBarItemTag]) -> Group? {
        groups(in: tags).first { $0.memberIndices.contains(index) }
    }

    /// Moves the block of elements at `sourceRange` so it begins at
    /// `destinationIndex`, expressed in the *original* array's index space.
    ///
    /// `destinationIndex` is where the block's first element should land
    /// relative to the untouched array (the same convention as a drop cursor).
    /// The block's internal order is preserved. Returns the reordered array.
    ///
    /// This is the block-move primitive behind "move the whole group": callers
    /// resolve a group's `range` and a drop position, then apply it to their
    /// ordered identifier/item array.
    static func moveBlock<Element>(
        _ elements: [Element],
        sourceRange: Range<Int>,
        toIndexInOriginal destinationIndex: Int
    ) -> [Element] {
        guard !sourceRange.isEmpty,
              sourceRange.lowerBound >= 0,
              sourceRange.upperBound <= elements.count
        else {
            return elements
        }
        let block = Array(elements[sourceRange])
        var remainder = elements
        remainder.removeSubrange(sourceRange)

        // Translate the destination from original-array space into remainder
        // space by discounting the removed elements whose original index sits
        // before the destination.
        let removedBefore = max(0, min(destinationIndex, sourceRange.upperBound) - sourceRange.lowerBound)
        let insertionIndex = (destinationIndex - removedBefore)
            .clamped(to: 0 ... remainder.count)

        remainder.insert(contentsOf: block, at: insertionIndex)
        return remainder
    }
}
