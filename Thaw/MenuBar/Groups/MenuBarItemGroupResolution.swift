//
//  MenuBarItemGroupResolution.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MenuBarItemGroupOrigin

/// Where a resolved group came from.
nonisolated enum MenuBarItemGroupOrigin: Hashable, Sendable, CustomStringConvertible {
    /// Derived from a shared bundle namespace by ``MenuBarItemGrouping``.
    /// Recomputed every layout pass; never stored.
    case automatic(MenuBarItemTag.Namespace)
    /// Authored by the user and persisted in ``MenuBarItemGroupSet``.
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
///
/// Deliberately shaped like ``MenuBarItemGrouping/Group`` so the layout bar's
/// existing chrome and handle code can adopt it with minimal disturbance.
nonisolated struct ResolvedGroup: Equatable, Sendable {
    let origin: MenuBarItemGroupOrigin
    /// The user-chosen name, or `nil` when the caller should derive one from the
    /// members (an automatic cluster, or a user group the user never named).
    let displayName: String?
    let isCollapsed: Bool
    /// Indices into the source array, ascending. Members are not necessarily
    /// contiguous — an automatic cluster is only gathered when it is moved.
    let memberIndices: [Int]

    var count: Int {
        memberIndices.count
    }

    /// The half-open span from first to last member. May enclose non-members
    /// when the group is not yet contiguous.
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

/// The single authority for "what groups exist in this ordered section?".
///
/// Every consumer — cluster chrome, drag handles, the drop handler, the order
/// canonicalizer — asks this type, so there is exactly one answer. User groups
/// are resolved first and claim their members; automatic bundle clusters then
/// fill in for whatever is left, unless the user dissolved that bundle's
/// cluster.
nonisolated enum MenuBarItemGroupResolver {
    /// Resolves `groupSet` against a live, ordered tag sequence.
    ///
    /// With an empty `groupSet` this reproduces ``MenuBarItemGrouping/groups(in:)``
    /// exactly — that equivalence is the regression lock protecting today's
    /// behaviour while the store is still empty in the field.
    static func resolve(
        tags: [MenuBarItemTag],
        groupSet: MenuBarItemGroupSet
    ) -> [ResolvedGroup] {
        var claimed = Set<Int>()
        var resolved = [ResolvedGroup]()

        // 1. User groups, in authored order, claim their members first.
        if !groupSet.groups.isEmpty {
            var indicesByIdentifier = [String: [Int]]()
            for (index, tag) in tags.enumerated() where MenuBarItemGrouping.isGroupable(tag) {
                indicesByIdentifier[tag.tagIdentifier, default: []].append(index)
            }

            for group in groupSet.groups {
                var memberIndices = [Int]()
                for identifier in group.memberIdentifiers {
                    guard let candidates = indicesByIdentifier[identifier] else { continue }
                    // A canonical identifier can match more than one live tag
                    // (same app, same canonicalized title, distinct windows).
                    // Take every unclaimed match so a group never silently
                    // leaves a duplicate sibling behind.
                    for candidate in candidates where !claimed.contains(candidate) {
                        memberIndices.append(candidate)
                    }
                }
                // Fewer than two *resolvable* members just means the owning app
                // isn't running. Skip rendering it; never mutate the store here.
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

        // 2. Automatic bundle clusters over whatever the user groups left.
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

        // 3. Left-to-right by first member, matching `groups(in:)`'s contract.
        return resolved.sorted { lhs, rhs in
            (lhs.memberIndices.first ?? 0) < (rhs.memberIndices.first ?? 0)
        }
    }

    /// The group containing the item at `index`, if any.
    static func group(
        containing index: Int,
        tags: [MenuBarItemTag],
        groupSet: MenuBarItemGroupSet
    ) -> ResolvedGroup? {
        resolve(tags: tags, groupSet: groupSet).first { $0.contains(index) }
    }

    /// The indices a single drag moves as one block: every member of the group
    /// containing `index`, or just `index` when it belongs to no group.
    ///
    /// This is what makes "a member drag is a group drag" true for both the
    /// mid-drag preview and the committed drop — the two must agree, or the
    /// preview lies about what will happen.
    static func dragUnitIndices(forIndex index: Int, in groups: [ResolvedGroup]) -> [Int] {
        groups.first { $0.contains(index) }?.memberIndices ?? [index]
    }

    /// Gathers `memberIndices` out of `elements` and reinserts them as one
    /// contiguous block beginning at `destinationIndex`, expressed in the
    /// *original* array's index space (the drop-cursor convention).
    ///
    /// Unlike ``MenuBarItemGrouping/moveBlock(_:sourceRange:toIndexInOriginal:)``
    /// the members need not be contiguous to begin with, so this both gathers a
    /// scattered group and moves it in one step. Members keep their relative
    /// order; so do non-members.
    static func placeBlock<Element>(
        _ elements: [Element],
        memberIndices: [Int],
        toIndexInOriginal destinationIndex: Int
    ) -> [Element] {
        let members = Set(memberIndices.filter { elements.indices.contains($0) })
        guard !members.isEmpty else { return elements }

        let block = memberIndices.filter { members.contains($0) }.map { elements[$0] }
        var remainder = [Element]()
        remainder.reserveCapacity(elements.count - block.count)
        // How many removed elements sat strictly before the destination —
        // that is the shift the destination has to absorb.
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
