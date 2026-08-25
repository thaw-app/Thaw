//
//  MenuBarItemGroupManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// Owns the persisted ``MenuBarItemGroupSet`` and is the app-side entry point
/// for resolving and editing menu bar item groups.
///
/// The pure rules live in `MenuBarModel` (``MenuBarItemGroupSet``,
/// ``MenuBarItemGroupResolver``); this type only adds persistence, publishing,
/// and the app-layer conveniences that need live `MenuBarItem`s.
@MainActor
@Observable
final class MenuBarItemGroupManager {
    static let diagLog = DiagLog(category: "MenuBarItemGroupManager")

    /// The authored group state. Every mutation normalizes, publishes, and
    /// persists in one step.
    private(set) var groupSet = MenuBarItemGroupSet.empty

    private let defaults: UserDefaults
    nonisolated private static let storageKey = "MenuBarItemGroups"

    /// - Parameter defaults: injectable so tests can use an isolated suite
    ///   instead of the app's real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            // No key at all is the overwhelmingly common case and means
            // "no groups" — identical behaviour to before this feature.
            return
        }

        let decoded: MenuBarItemGroupSet
        do {
            decoded = try JSONDecoder().decode(MenuBarItemGroupSet.self, from: data)
        } catch {
            // Deliberately do NOT remove the key: a future build may understand
            // a payload this one cannot, and silently deleting a user's groups
            // is far worse than starting empty for one launch.
            Self.diagLog.error("failed to decode persisted groups, starting empty: \(error)")
            return
        }

        guard decoded.version <= MenuBarItemGroupSet.currentVersion else {
            Self.diagLog.notice(
                "persisted groups are version \(decoded.version) > \(MenuBarItemGroupSet.currentVersion); " +
                    "ignoring them this launch and leaving the stored value untouched"
            )
            return
        }

        groupSet = decoded
        if !decoded.groups.isEmpty || !decoded.suppressedAutomaticNamespaces.isEmpty {
            Self.diagLog.info(
                "loaded \(decoded.groups.count) group(s), " +
                    "\(decoded.suppressedAutomaticNamespaces.count) suppressed namespace(s)"
            )
        }
    }

    private func persist() {
        // An empty set is the default, so clear the key rather than storing an
        // empty document — that keeps `defaults read` output honest and makes
        // "never used groups" indistinguishable from "reset groups".
        guard groupSet != .empty else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        do {
            try defaults.set(JSONEncoder().encode(groupSet), forKey: Self.storageKey)
        } catch {
            Self.diagLog.error("failed to encode groups: \(error)")
        }
    }

    private func commit(_ updated: MenuBarItemGroupSet) {
        guard updated != groupSet else { return }
        groupSet = updated
        persist()
    }

    // MARK: Resolution

    /// The groups present in an ordered run of live items.
    func resolvedGroups(for items: [MenuBarItem]) -> [ResolvedGroup] {
        MenuBarItemGroupResolver.resolve(tags: items.map(\.tag), groupSet: groupSet)
    }

    /// The group containing `item` within `items`, if any.
    func resolvedGroup(containing item: MenuBarItem, in items: [MenuBarItem]) -> ResolvedGroup? {
        guard let index = items.firstIndex(where: { $0.tag == item.tag }) else { return nil }
        return MenuBarItemGroupResolver.group(containing: index, tags: items.map(\.tag), groupSet: groupSet)
    }

    /// The items a drag starting on `item` moves as one block, in `items` order.
    /// Returns just `item` when it belongs to no group.
    func dragUnit(for item: MenuBarItem, in items: [MenuBarItem]) -> [MenuBarItem] {
        guard let index = items.firstIndex(where: { $0.tag == item.tag }) else { return [item] }
        let groups = resolvedGroups(for: items)
        return MenuBarItemGroupResolver
            .dragUnitIndices(forIndex: index, in: groups)
            .compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    /// A name to show for `group`, falling back to the owning app when the user
    /// has not named it. Derived rather than stored, so an app rename is picked
    /// up without rewriting the store.
    func displayName(for group: ResolvedGroup, in items: [MenuBarItem]) -> String {
        if let name = group.displayName {
            return name
        }
        let members = group.memberIndices.compactMap { items.indices.contains($0) ? items[$0] : nil }
        if let owner = members.compactMap({ $0.sourceApplication?.localizedName }).first {
            return owner
        }
        if let detected = members.first?.autoDetectedName {
            return detected
        }
        return String(localized: "\(group.count) items", comment: "Fallback name for an unnamed item group")
    }

    // MARK: Editing

    /// Creates a group from `items`. Returns `nil` when fewer than two distinct
    /// groupable identifiers remain.
    @discardableResult
    func createGroup(name: String?, items: [MenuBarItem]) -> MenuBarItemGroup? {
        let groupable = items.filter { MenuBarItemGrouping.isGroupable($0.tag) }
        var updated = groupSet
        let created = updated.createGroup(
            name: name,
            memberIdentifiers: groupable.map(\.uniqueIdentifier)
        )
        guard created != nil else {
            Self.diagLog.warning(
                "refusing to create a group from \(items.count) item(s): fewer than two are groupable"
            )
            return nil
        }
        commit(updated)
        Self.diagLog.info("created group with \(created?.memberIdentifiers.count ?? 0) member(s)")
        return created
    }

    func add(_ item: MenuBarItem, to id: UUID, at index: Int? = nil) {
        guard MenuBarItemGrouping.isGroupable(item.tag) else {
            Self.diagLog.warning("refusing to add non-groupable \(item.logString) to a group")
            return
        }
        var updated = groupSet
        updated.add(item.uniqueIdentifier, to: id, at: index)
        commit(updated)
    }

    func removeMember(_ item: MenuBarItem) {
        removeMemberIdentifier(item.uniqueIdentifier)
    }

    /// Removes a member by identifier, for the case where no live item exists —
    /// the owning app is not running, but the user still wants it out of the
    /// group.
    func removeMemberIdentifier(_ identifier: String) {
        var updated = groupSet
        updated.removeMember(identifier)
        commit(updated)
    }

    /// Dissolves a group. For an automatic cluster this records a suppression so
    /// it does not simply re-derive on the next layout pass.
    func ungroup(_ origin: MenuBarItemGroupOrigin) {
        var updated = groupSet
        switch origin {
        case let .user(id):
            updated.dissolve(id: id)
        case let .automatic(namespace):
            updated.suppressAutomatic(namespace)
        }
        commit(updated)
        Self.diagLog.info("ungrouped \(origin.description)")
    }

    func rename(_ origin: MenuBarItemGroupOrigin, to name: String?, members: [MenuBarItem]) {
        var updated = groupSet
        switch origin {
        case let .user(id):
            updated.rename(id: id, to: name)
        case .automatic:
            // Editing an automatic cluster materializes it into a real user
            // group carrying its current members. Deliberately NOT done for
            // every cluster at launch: that would freeze the bundle's future
            // items out of their own group forever.
            guard let id = materialize(origin, members: members, in: &updated) else { return }
            updated.rename(id: id, to: name)
        }
        commit(updated)
    }

    func setCollapsed(_ isCollapsed: Bool, for origin: MenuBarItemGroupOrigin, members: [MenuBarItem]) {
        var updated = groupSet
        switch origin {
        case let .user(id):
            updated.setCollapsed(isCollapsed, id: id)
        case .automatic:
            guard let id = materialize(origin, members: members, in: &updated) else { return }
            updated.setCollapsed(isCollapsed, id: id)
        }
        commit(updated)
    }

    /// Converts an automatic cluster into a user group over its current members
    /// and suppresses the bundle so both do not resolve at once.
    private func materialize(
        _ origin: MenuBarItemGroupOrigin,
        members: [MenuBarItem],
        in set: inout MenuBarItemGroupSet
    ) -> UUID? {
        guard case let .automatic(namespace) = origin else { return nil }
        let identifiers = members
            .filter { MenuBarItemGrouping.isGroupable($0.tag) }
            .map(\.uniqueIdentifier)
        guard let created = set.createGroup(name: nil, memberIdentifiers: identifiers) else {
            Self.diagLog.warning("cannot materialize automatic group \(namespace.description): too few members")
            return nil
        }
        set.suppressAutomatic(namespace)
        Self.diagLog.info("materialized automatic group \(namespace.description) into a user group")
        return created.id
    }

    // MARK: Profiles

    func snapshot() -> MenuBarItemGroupSet {
        groupSet
    }

    func apply(_ set: MenuBarItemGroupSet?) {
        commit(set ?? .empty)
    }
}
