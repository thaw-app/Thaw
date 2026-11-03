//
//  MenuBarItemGroup.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MenuBarItemGroup

/// A user-authored group of menu bar items.
///
/// Unlike the automatic per-bundle clusters, which are recomputed every pass
/// and never stored, a user group has stored identity and can span bundles.
public struct MenuBarItemGroup: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity. Survives renames, membership changes, and the group
    /// having no live members at all.
    public let id: UUID

    /// The user-chosen name, or nil to derive one at display time from the
    /// members. Derived names are never stored, so an app rename is picked up.
    public var name: String?

    /// Canonical tagIdentifier strings, in authored left-to-right order.
    ///
    /// Canonicalized the same way as the persisted section order; if the two
    /// disagree, membership silently dissolves for apps whose titles churn.
    public private(set) var memberIdentifiers: [String]

    /// Whether the layout editor draws the group as one collapsed pill.
    /// Presentation only; never affects the persisted section order.
    public var isCollapsed: Bool

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        memberIdentifiers: [String],
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.memberIdentifiers = MenuBarItemTag.canonicalPersistentIdentifiers(memberIdentifiers)
        self.isCollapsed = isCollapsed
    }

    /// Trims a display name, mapping blank to nil so "no name" has exactly one
    /// representation. Mirrors how MenuBarItem.customName treats blanks.
    static func normalizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    /// Inserts identifier at index (appending when nil), removing any
    /// existing occurrence first so a member can be repositioned in one call.
    public mutating func insert(_ identifier: String, at index: Int? = nil) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        var members = memberIdentifiers
        members.removeAll { $0 == identifier }
        let target = (index ?? members.count).clamped(to: 0 ... members.count)
        members.insert(identifier, at: target)
        memberIdentifiers = members
    }

    public mutating func remove(_ identifier: String) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        memberIdentifiers.removeAll { $0 == identifier }
    }

    /// Reorders a member within the group, leaving every other member's
    /// relative order untouched.
    public mutating func moveMember(from source: Int, to destination: Int) {
        guard memberIdentifiers.indices.contains(source) else { return }
        var members = memberIdentifiers
        let moved = members.remove(at: source)
        let target = destination.clamped(to: 0 ... members.count)
        members.insert(moved, at: target)
        memberIdentifiers = members
    }

    public func contains(_ identifier: String) -> Bool {
        memberIdentifiers.contains(MenuBarItemTag.canonicalPersistentIdentifier(identifier))
    }
}

// MARK: - MenuBarItemGroupSet

/// The complete authored group state: every user group, plus the bundles whose
/// automatic cluster the user has explicitly dissolved.
///
/// Pure and Codable so it round-trips through defaults and profiles and can be
/// unit-tested without AppKit, AppState, or a live menu bar.
public struct MenuBarItemGroupSet: Codable, Equatable, Sendable {
    /// Bumped only for changes the decoder cannot absorb. A newer version reads
    /// as "no groups" without rewriting storage, so a downgrade loses nothing.
    public static let currentVersion = 1

    public var version: Int

    /// User groups in authored order. Order is meaningful: when two groups
    /// claim the same identifier, the earlier one wins.
    public private(set) var groups: [MenuBarItemGroup]

    /// Namespace descriptions whose automatic cluster the user dissolved.
    /// Without this, the next layout pass re-derives the cluster and undoes "Ungroup".
    public private(set) var suppressedAutomaticNamespaces: Set<String>

    public static let empty = MenuBarItemGroupSet()

    public init(
        version: Int = MenuBarItemGroupSet.currentVersion,
        groups: [MenuBarItemGroup] = [],
        suppressedAutomaticNamespaces: Set<String> = []
    ) {
        self.version = version
        self.groups = groups
        self.suppressedAutomaticNamespaces = suppressedAutomaticNamespaces
        self = normalized()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        groups = try container.decodeIfPresent([MenuBarItemGroup].self, forKey: .groups) ?? []
        suppressedAutomaticNamespaces = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .suppressedAutomaticNamespaces
        ) ?? []
        self = normalized()
    }

    /// Canonicalizes and de-duplicates members, gives each identifier to the
    /// earliest group only, drops groups under two stored members, trims names.
    ///
    /// Counts stored members, not live ones: quitting an app must not delete
    /// its group. Applied on decode, after every mutation, and before encode.
    public func normalized() -> MenuBarItemGroupSet {
        var claimed = Set<String>()
        var normalizedGroups = [MenuBarItemGroup]()

        for group in groups {
            let members = MenuBarItemTag
                .canonicalPersistentIdentifiers(group.memberIdentifiers)
                .filter { claimed.insert($0).inserted }
            guard members.count >= 2 else { continue }
            normalizedGroups.append(
                MenuBarItemGroup(
                    id: group.id,
                    name: group.name,
                    memberIdentifiers: members,
                    isCollapsed: group.isCollapsed
                )
            )
        }

        return MenuBarItemGroupSet(
            uncheckedVersion: max(version, Self.currentVersion),
            groups: normalizedGroups,
            suppressedAutomaticNamespaces: suppressedAutomaticNamespaces
        )
    }

    /// Bypasses init's normalization so normalized() cannot recurse.
    private init(
        uncheckedVersion: Int,
        groups: [MenuBarItemGroup],
        suppressedAutomaticNamespaces: Set<String>
    ) {
        version = uncheckedVersion
        self.groups = groups
        self.suppressedAutomaticNamespaces = suppressedAutomaticNamespaces
    }

    // MARK: Queries

    public func group(containing identifier: String) -> MenuBarItemGroup? {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        return groups.first { $0.memberIdentifiers.contains(identifier) }
    }

    public func group(id: UUID) -> MenuBarItemGroup? {
        groups.first { $0.id == id }
    }

    public func isSuppressedAutomaticNamespace(_ namespace: MenuBarItemTag.Namespace) -> Bool {
        suppressedAutomaticNamespaces.contains(namespace.description)
    }

    // MARK: Mutations

    /// Creates a group from memberIdentifiers, stealing any of them from the
    /// groups that currently hold them. Returns nil when fewer than two
    /// distinct identifiers remain after canonicalization.
    @discardableResult
    public mutating func createGroup(name: String?, memberIdentifiers: [String]) -> MenuBarItemGroup? {
        let members = MenuBarItemTag.canonicalPersistentIdentifiers(memberIdentifiers)
        guard members.count >= 2 else { return nil }
        for member in members {
            removeFromAllGroups(member)
        }
        let group = MenuBarItemGroup(name: name, memberIdentifiers: members)
        groups.append(group)
        self = normalized()
        return groups.first { $0.id == group.id }
    }

    public mutating func add(_ identifier: String, to id: UUID, at index: Int? = nil) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        removeFromAllGroups(identifier, exceptGroupAt: position)
        groups[position].insert(identifier, at: index)
        self = normalized()
    }

    /// Removes a member. A group that drops below two members dissolves, which
    /// normalized() handles.
    public mutating func removeMember(_ identifier: String) {
        removeFromAllGroups(identifier)
        self = normalized()
    }

    public mutating func dissolve(id: UUID) {
        groups.removeAll { $0.id == id }
        self = normalized()
    }

    public mutating func rename(id: UUID, to name: String?) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].name = MenuBarItemGroup.normalizedName(name)
    }

    public mutating func setCollapsed(_ isCollapsed: Bool, id: UUID) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].isCollapsed = isCollapsed
    }

    public mutating func moveMember(in id: UUID, from source: Int, to destination: Int) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].moveMember(from: source, to: destination)
    }

    /// Suppresses a bundle's automatic cluster so "Ungroup" survives the next
    /// layout pass.
    public mutating func suppressAutomatic(_ namespace: MenuBarItemTag.Namespace) {
        suppressedAutomaticNamespaces.insert(namespace.description)
    }

    public mutating func unsuppressAutomatic(_ namespace: MenuBarItemTag.Namespace) {
        suppressedAutomaticNamespaces.remove(namespace.description)
    }

    private mutating func removeFromAllGroups(_ identifier: String, exceptGroupAt keep: Int? = nil) {
        for index in groups.indices where index != keep {
            groups[index].remove(identifier)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case groups
        case suppressedAutomaticNamespaces
    }
}
