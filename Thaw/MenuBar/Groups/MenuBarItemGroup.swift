//
//  MenuBarItemGroup.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MenuBarItemGroup

/// A user-authored group of menu bar items.
///
/// Unlike the automatic clusters ``MenuBarItemGrouping`` derives from a shared
/// bundle namespace, a user group has explicit identity and can span any number
/// of bundles. Automatic clusters are recomputed from live tags on every layout
/// pass and are never stored; only groups the user actually authored are.
nonisolated struct MenuBarItemGroup: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity. Survives renames, membership changes, and the group
    /// having no live members at all.
    let id: UUID

    /// The user-chosen name, or `nil` to derive one at display time from the
    /// members. Derived names are never stored, so an app rename is picked up.
    var name: String?

    /// Canonical `tagIdentifier` strings, in authored left-to-right order.
    ///
    /// Always canonicalized through ``MenuBarItemTag/canonicalPersistentIdentifiers(_:)``
    /// — the *same* function the persisted section order is canonicalized with.
    /// If the two ever disagree, membership silently dissolves for apps whose
    /// titles churn (iStat Menus and friends), which is the single sharpest
    /// failure mode in this model.
    private(set) var memberIdentifiers: [String]

    /// Whether the layout editor draws the group as one collapsed pill.
    /// Presentation only — never affects the persisted section order.
    var isCollapsed: Bool

    init(
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

    /// Trims a display name, mapping blank to `nil` so "no name" has exactly one
    /// representation. Mirrors how `MenuBarItem.customName` treats blanks.
    static func normalizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    /// Inserts `identifier` at `index` (appending when `nil`), removing any
    /// existing occurrence first so a member can be repositioned in one call.
    mutating func insert(_ identifier: String, at index: Int? = nil) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        var members = memberIdentifiers
        members.removeAll { $0 == identifier }
        let target = (index ?? members.count).clamped(to: 0 ... members.count)
        members.insert(identifier, at: target)
        memberIdentifiers = members
    }

    mutating func remove(_ identifier: String) {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        memberIdentifiers.removeAll { $0 == identifier }
    }

    /// Reorders a member within the group, leaving every other member's
    /// relative order untouched.
    mutating func moveMember(from source: Int, to destination: Int) {
        guard memberIdentifiers.indices.contains(source) else { return }
        var members = memberIdentifiers
        let moved = members.remove(at: source)
        let target = destination.clamped(to: 0 ... members.count)
        members.insert(moved, at: target)
        memberIdentifiers = members
    }

    func contains(_ identifier: String) -> Bool {
        memberIdentifiers.contains(MenuBarItemTag.canonicalPersistentIdentifier(identifier))
    }
}

// MARK: - MenuBarItemGroupSet

/// The complete authored group state: every user group, plus the bundles whose
/// automatic cluster the user has explicitly dissolved.
///
/// Pure and `Codable` so it round-trips through defaults and profiles and can be
/// unit-tested without AppKit, `AppState`, or a live menu bar.
nonisolated struct MenuBarItemGroupSet: Codable, Equatable, Sendable {
    /// Bumped only for changes the decoder cannot absorb. A newer version than
    /// this build understands is treated as "no groups" *without* rewriting the
    /// stored value, so downgrading never destroys a newer build's data.
    static let currentVersion = 1

    var version: Int

    /// User groups in authored order. Order is meaningful: when two groups
    /// claim the same identifier, the earlier one wins.
    private(set) var groups: [MenuBarItemGroup]

    /// Bundle namespace descriptions (`MenuBarItemTag.Namespace.description`)
    /// whose automatic cluster the user dissolved. Without this, "Ungroup" on an
    /// automatic cluster would be undone on the very next layout pass, since
    /// automatic clusters are re-derived from live tags every time.
    private(set) var suppressedAutomaticNamespaces: Set<String>

    static let empty = MenuBarItemGroupSet()

    init(
        version: Int = MenuBarItemGroupSet.currentVersion,
        groups: [MenuBarItemGroup] = [],
        suppressedAutomaticNamespaces: Set<String> = []
    ) {
        self.version = version
        self.groups = groups
        self.suppressedAutomaticNamespaces = suppressedAutomaticNamespaces
        self = normalized()
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        groups = try container.decodeIfPresent([MenuBarItemGroup].self, forKey: .groups) ?? []
        suppressedAutomaticNamespaces = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .suppressedAutomaticNamespaces
        ) ?? []
        self = normalized()
    }

    /// Re-establishes every structural invariant:
    ///
    /// - member identifiers are canonicalized and de-duplicated within a group;
    /// - an identifier belongs to at most one group (earlier group wins);
    /// - a group left with fewer than two *stored* members is dropped;
    /// - names are trimmed, blank becoming `nil`.
    ///
    /// Note the asymmetry that keeps this safe: fewer than two **stored**
    /// members means the record was already degenerate and is dropped, but
    /// fewer than two **resolvable** members merely means the owning app is not
    /// running — those groups are kept untouched. Pruning on resolvability
    /// would delete a user's group simply because they quit an app.
    ///
    /// Applied on decode, after every mutation, and before encode, so the
    /// in-memory and on-disk forms are always identical.
    func normalized() -> MenuBarItemGroupSet {
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

    /// Bypasses `init`'s normalization so `normalized()` cannot recurse.
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

    func group(containing identifier: String) -> MenuBarItemGroup? {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
        return groups.first { $0.memberIdentifiers.contains(identifier) }
    }

    func group(id: UUID) -> MenuBarItemGroup? {
        groups.first { $0.id == id }
    }

    func isSuppressedAutomaticNamespace(_ namespace: MenuBarItemTag.Namespace) -> Bool {
        suppressedAutomaticNamespaces.contains(namespace.description)
    }

    // MARK: Mutations

    /// Creates a group from `memberIdentifiers`, stealing any of them from the
    /// groups that currently hold them. Returns `nil` when fewer than two
    /// distinct identifiers remain after canonicalization.
    @discardableResult
    mutating func createGroup(name: String?, memberIdentifiers: [String]) -> MenuBarItemGroup? {
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

    mutating func add(_ identifier: String, to id: UUID, at index: Int? = nil) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        removeFromAllGroups(identifier, exceptGroupAt: position)
        groups[position].insert(identifier, at: index)
        self = normalized()
    }

    /// Removes a member. A group that drops below two members dissolves, which
    /// `normalized()` handles.
    mutating func removeMember(_ identifier: String) {
        removeFromAllGroups(identifier)
        self = normalized()
    }

    mutating func dissolve(id: UUID) {
        groups.removeAll { $0.id == id }
        self = normalized()
    }

    mutating func rename(id: UUID, to name: String?) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].name = MenuBarItemGroup.normalizedName(name)
    }

    mutating func setCollapsed(_ isCollapsed: Bool, id: UUID) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].isCollapsed = isCollapsed
    }

    mutating func moveMember(in id: UUID, from source: Int, to destination: Int) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].moveMember(from: source, to: destination)
    }

    /// Suppresses a bundle's automatic cluster so "Ungroup" survives the next
    /// layout pass.
    mutating func suppressAutomatic(_ namespace: MenuBarItemTag.Namespace) {
        suppressedAutomaticNamespaces.insert(namespace.description)
    }

    mutating func unsuppressAutomatic(_ namespace: MenuBarItemTag.Namespace) {
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
