//
//  MenuBarItemGroupResolution.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MenuBarItemGroupOrigin

/// Where a resolved group came from.
public enum MenuBarItemGroupOrigin: Hashable, Sendable, CustomStringConvertible {
    /// Derived from a shared bundle namespace by MenuBarItemGrouping.
    /// Recomputed every layout pass; never stored.
    case automatic(MenuBarItemTag.Namespace)
    /// Authored by the user and persisted in MenuBarItemGroupSet.
    case user(UUID)

    public var isUserAuthored: Bool {
        switch self {
        case .automatic: false
        case .user: true
        }
    }

    public var description: String {
        switch self {
        case let .automatic(namespace): "automatic:\(namespace.description)"
        case let .user(id): "group:\(id.uuidString)"
        }
    }
}

// MARK: - ResolvedGroup

/// A group resolved against one ordered sequence, shaped like MenuBarItemGrouping.Group for shared layout UI.
public struct ResolvedGroup: Equatable, Sendable {
    public let origin: MenuBarItemGroupOrigin
    /// Nil for automatic or unnamed groups; callers derive a name from the members.
    public let displayName: String?
    public let isCollapsed: Bool
    /// Ascending source indices; members may be scattered until a move gathers them.
    public let memberIndices: [Int]

    public init(
        origin: MenuBarItemGroupOrigin,
        displayName: String?,
        isCollapsed: Bool,
        memberIndices: [Int]
    ) {
        self.origin = origin
        self.displayName = displayName
        self.isCollapsed = isCollapsed
        self.memberIndices = memberIndices
    }

    public var count: Int {
        memberIndices.count
    }

    /// The half-open member span, which may enclose non-members in scattered groups.
    public var range: Range<Int> {
        guard let first = memberIndices.first, let last = memberIndices.last else {
            return 0 ..< 0
        }
        return first ..< (last + 1)
    }

    public func contains(_ index: Int) -> Bool {
        memberIndices.contains(index)
    }
}

// MARK: - MenuBarItemGroupResolver

/// Shared group resolution for cluster UI, dragging, and order canonicalization.
/// User groups claim members first; unsuppressed automatic clusters fill the remainder.
public enum MenuBarItemGroupResolver {
    /// An empty groupSet resolves exactly like MenuBarItemGrouping.groups(in:).
    public static func resolve(
        tags: [MenuBarItemTag],
        groupSet: MenuBarItemGroupSet
    ) -> [ResolvedGroup] {
        var claimed = Set<Int>()
        var resolved = [ResolvedGroup]()

        // User groups, in authored order, claim their members first.
        if !groupSet.groups.isEmpty {
            var indicesByIdentifier = [String: [Int]]()
            for (index, tag) in tags.enumerated() where MenuBarItemGrouping.isGroupable(tag) {
                indicesByIdentifier[tag.tagIdentifier, default: []].append(index)
            }

            for group in groupSet.groups {
                var memberIndices = [Int]()
                for identifier in group.memberIdentifiers {
                    guard let candidates = indicesByIdentifier[identifier] else { continue }
                    // Distinct windows can share a canonical identifier; claim every matching sibling.
                    for candidate in candidates where !claimed.contains(candidate) {
                        memberIndices.append(candidate)
                    }
                }
                // Missing apps can leave fewer than two members; skip rendering without changing the store.
                guard memberIndices.count >= 2 else { continue }
                memberIndices.sort()
                claimed.formUnion(memberIndices)
                resolved.append(
                    ResolvedGroup(
                        origin: .user(group.id),
                        displayName: group.name,
                        isCollapsed: group.isCollapsed,
                        memberIndices: memberIndices
                    )
                )
            }
        }

        // Automatic bundle clusters over whatever the user groups left.
        for group in MenuBarItemGrouping.groups(in: tags) {
            guard !groupSet.isSuppressedAutomaticNamespace(group.namespace) else { continue }
            let remaining = group.memberIndices.filter { !claimed.contains($0) }
            guard remaining.count >= 2 else { continue }
            claimed.formUnion(remaining)
            resolved.append(
                ResolvedGroup(
                    origin: .automatic(group.namespace),
                    displayName: nil,
                    isCollapsed: false,
                    memberIndices: remaining
                )
            )
        }

        // Left-to-right by first member, matching groups(in:)'s contract.
        return resolved.sorted { lhs, rhs in
            (lhs.memberIndices.first ?? 0) < (rhs.memberIndices.first ?? 0)
        }
    }

    public static func group(
        containing index: Int,
        tags: [MenuBarItemTag],
        groupSet: MenuBarItemGroupSet
    ) -> ResolvedGroup? {
        resolve(tags: tags, groupSet: groupSet).first { $0.contains(index) }
    }

    /// Moves all group members, or just index for an ungrouped item.
    /// Shared by drag preview and drop commit so both move the same items.
    public static func dragUnitIndices(forIndex index: Int, in groups: [ResolvedGroup]) -> [Int] {
        groups.first { $0.contains(index) }?.memberIndices ?? [index]
    }

    /// Gathers scattered members into one block at a destination in the original array's index space.
    /// Preserves relative order within members and non-members.
    public static func placeBlock<Element>(
        _ elements: [Element],
        memberIndices: [Int],
        toIndexInOriginal destinationIndex: Int
    ) -> [Element] {
        let members = Set(memberIndices.filter { elements.indices.contains($0) })
        guard !members.isEmpty else { return elements }

        let block = memberIndices.filter { members.contains($0) }.map { elements[$0] }
        var remainder = [Element]()
        remainder.reserveCapacity(elements.count - block.count)
        // Removed elements before the destination shift its insertion index.
        var removedBefore = 0
        for (index, element) in elements.enumerated() {
            if members.contains(index) {
                if index < destinationIndex {
                    removedBefore += 1
                }
            } else {
                remainder.append(element)
            }
        }

        let insertionIndex = (destinationIndex - removedBefore)
            .clamped(to: 0 ... remainder.count)
        remainder.insert(contentsOf: block, at: insertionIndex)
        return remainder
    }
}
