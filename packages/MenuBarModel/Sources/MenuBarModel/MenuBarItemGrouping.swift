//
//  MenuBarItemGrouping.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Groups same-bundle items within a section so the UI can gather scattered members into one movable cluster.
/// Pure, tag-driven rules allow tests without a live menu bar or AppKit views.
public enum MenuBarItemGrouping {
    /// A set of same-bundle items within an ordered sequence.
    public struct Group: Equatable, Sendable {
        /// The shared namespace (bundle identity) of the members.
        public let namespace: MenuBarItemTag.Namespace
        /// Ascending indices in the source array; members need not be contiguous.
        public let memberIndices: [Int]

        public init(namespace: MenuBarItemTag.Namespace, memberIndices: [Int]) {
            self.namespace = namespace
            self.memberIndices = memberIndices
        }

        public var count: Int {
            memberIndices.count
        }

        /// Half-open span for the cluster background and handle; may enclose non-members.
        public var range: Range<Int> {
            guard let first = memberIndices.first, let last = memberIndices.last else {
                return 0 ..< 0
            }
            return first ..< (last + 1)
        }
    }

    /// Only third-party apps group; system and MenuBarAgent namespaces would merge unrelated Apple modules.
    /// Excludes Thaw controls, fixed anchors, immovable items, and UUID or null namespaces.
    public static func isGroupable(_ tag: MenuBarItemTag) -> Bool {
        guard tag.namespace.isString else { return false }
        guard !tag.isSystemItem else { return false }
        guard tag.namespace != .menuBarAgent else { return false }
        guard !tag.isThawOwnedNamespace else { return false }
        guard !tag.isLayoutAnchoredSystemItem else { return false }
        return tag.isMovable
    }

    /// Returns one group per bundle with at least two groupable items, ordered by first member.
    /// Includes nonadjacent siblings but never non-groupable items.
    public static func groups(in tags: [MenuBarItemTag]) -> [Group] {
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

    /// The group containing the item at index, if that item is part of one.
    public static func group(containing index: Int, in tags: [MenuBarItemTag]) -> Group? {
        groups(in: tags).first { $0.memberIndices.contains(index) }
    }

    /// Moves a block to a drop-cursor index in the original array, preserving internal order.
    /// Callers resolve the group range and drop position before reordering their items.
    public static func moveBlock<Element>(
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

        // Convert to remainder indices by subtracting removed elements before the destination.
        let removedBefore = max(0, min(destinationIndex, sourceRange.upperBound) - sourceRange.lowerBound)
        let insertionIndex = (destinationIndex - removedBefore)
            .clamped(to: 0 ... remainder.count)

        remainder.insert(contentsOf: block, at: insertionIndex)
        return remainder
    }
}
