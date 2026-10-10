//
//  MenuBarItemGroupResolution.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MenuBarItemGroupOrigin

/// Where a resolved group came from.
nonisolated enum MenuBarItemGroupOrigin: Hashable, Sendable, CustomStringConvertible {
    /// From ``MenuBarItemGrouping``. Recomputed every pass, never stored.
    case automatic(MenuBarItemTag.Namespace)
    /// Persisted in ``MenuBarItemGroupSet``.
    case user(UUID)

    var isUserAuthored: Bool {
        switch self {
        case .automatic: false
        case .user: true
        }
    }

    var description: String {
        switch self {
        case let .automatic(namespace): "automatic:\(namespace.description)"
        case let .user(id): "group:\(id.uuidString)"
        }
    }
}

// MARK: - ResolvedGroup

/// A group as it applies to one ordered sequence of items, right now.
/// Shaped like ``MenuBarItemGrouping/Group`` so the layout bar code can adopt it.
nonisolated struct ResolvedGroup: Equatable, Sendable {
    let origin: MenuBarItemGroupOrigin
    /// `nil` when the caller should derive one from the members.
    let displayName: String?
    let isCollapsed: Bool
    /// Ascending. Not necessarily contiguous; an automatic cluster is only
    /// gathered when moved.
    let memberIndices: [Int]

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

    func contains(_ index: Int) -> Bool {
        memberIndices.contains(index)
    }
}

// MARK: - MenuBarItemGroupResolver

/// The single authority for which groups exist in an ordered section.
///
/// User groups claim their members first; automatic bundle clusters fill in
/// the rest unless the user dissolved them.
nonisolated enum MenuBarItemGroupResolver {
    /// Resolves `groupSet` against a live, ordered tag sequence.
    ///
    /// With an empty `groupSet` this must match
    /// ``MenuBarItemGrouping/groups(in:)`` exactly.
    static func resolve(
        tags: [MenuBarItemTag],
        groupSet: MenuBarItemGroupSet
    ) -> [ResolvedGroup] {
        var claimed = Set<Int>()
        var resolved = [ResolvedGroup]()

        // User groups claim their members first.
        if !groupSet.groups.isEmpty {
            var indicesByIdentifier = [String: [Int]]()
            for (index, tag) in tags.enumerated() where MenuBarItemGrouping.isGroupable(tag) {
                indicesByIdentifier[tag.tagIdentifier, default: []].append(index)
            }

            for group in groupSet.groups {
                var memberIndices = [Int]()
                for identifier in group.memberIdentifiers {
                    guard let candidates = indicesByIdentifier[identifier] else { continue }
                    // One identifier can match several windows of the same
                    // app. Take them all so no sibling is left behind.
                    for candidate in candidates where !claimed.contains(candidate) {
                        memberIndices.append(candidate)
                    }
                }
                // The owning app isn't running. Skip, but never mutate the
                // store here.
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

        // Match `groups(in:)`: left to right by first member.
        return resolved.sorted { lhs, rhs in
            (lhs.memberIndices.first ?? 0) < (rhs.memberIndices.first ?? 0)
        }
    }

    static func group(
        containing index: Int,
        tags: [MenuBarItemTag],
        groupSet: MenuBarItemGroupSet
    ) -> ResolvedGroup? {
        resolve(tags: tags, groupSet: groupSet).first { $0.contains(index) }
    }

    /// The indices a drag moves as one block. The drag preview and the drop
    /// must both use this, or the preview lies.
    static func dragUnitIndices(forIndex index: Int, in groups: [ResolvedGroup]) -> [Int] {
        groups.first { $0.contains(index) }?.memberIndices ?? [index]
    }
}
