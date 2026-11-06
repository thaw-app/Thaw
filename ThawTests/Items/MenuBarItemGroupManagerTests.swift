//
//  MenuBarItemGroupManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("The group manager edits, resolves and persists item groups")
struct MenuBarItemGroupManagerTests {
    private let suites = ScratchSuites(prefix: "MenuBarItemGroupManagerTests")

    private func makeDefaults() throws -> UserDefaults {
        try #require(suites.make())
    }

    private func item(_ title: String, bundle: String = "com.example.groups", pid: pid_t = 999_997) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: CGWindowID(abs(title.hashValue % 10000) + 1),
            ownerPID: pid,
            sourcePID: pid,
            bounds: CGRect(x: 600, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private var storageKey: String {
        Defaults.Key.menuBarItemGroups.rawValue
    }

    @Test("A new manager over empty defaults has no groups")
    func startsEmpty() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        #expect(manager.groupSet == .empty)
        #expect(manager.snapshot() == .empty)
    }

    @Test("Creating a group persists it, and a new manager loads it back")
    func createPersistsAndLoads() throws {
        let defaults = try makeDefaults()
        let manager = MenuBarItemGroupManager(defaults: defaults)
        let first = item("A", bundle: "com.example.one")
        let second = item("B", bundle: "com.example.two")

        let created = try #require(manager.createGroup(name: "Pair", items: [first, second]))

        #expect(created.memberIdentifiers == [first.uniqueIdentifier, second.uniqueIdentifier])
        #expect(defaults.data(forKey: storageKey) != nil)
        let reloaded = MenuBarItemGroupManager(defaults: defaults)
        #expect(reloaded.groupSet == manager.groupSet)
        #expect(reloaded.groupSet.group(id: created.id)?.name == "Pair")
    }

    @Test("A group needs two groupable items")
    func createRefusesTooFew() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let spacer = MenuBarItem(
            tag: MenuBarItemTag(namespace: .thaw, title: MenuBarSpacerManager.autosavePrefix + "X", instanceIndex: 0),
            windowID: 77,
            ownerPID: 1,
            sourcePID: 1,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )
        #expect(manager.createGroup(name: nil, items: [item("Solo"), spacer]) == nil)
        #expect(manager.groupSet == .empty)
    }

    @Test("Members can be added and removed, and removing the last one clears the store")
    func addAndRemoveMembers() throws {
        let defaults = try makeDefaults()
        let manager = MenuBarItemGroupManager(defaults: defaults)
        let first = item("A", bundle: "com.example.one")
        let second = item("B", bundle: "com.example.two")
        let third = item("C", bundle: "com.example.three")
        let group = try #require(manager.createGroup(name: nil, items: [first, second]))

        manager.add(third, to: group.id, at: 0)
        #expect(manager.groupSet.group(id: group.id)?.memberIdentifiers.first == third.uniqueIdentifier)

        manager.removeMember(third)
        manager.removeMemberIdentifier(second.uniqueIdentifier)
        manager.ungroup(.user(group.id))

        #expect(manager.groupSet.groups.isEmpty)
        #expect(defaults.data(forKey: storageKey) == nil)
    }

    @Test("A non-groupable item is not added")
    func addRefusesNonGroupable() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let group = try #require(manager.createGroup(
            name: nil,
            items: [item("A", bundle: "com.example.one"), item("B", bundle: "com.example.two")]
        ))
        let before = manager.groupSet
        let anchored = MenuBarItem(
            tag: MenuBarItemTag(namespace: .uuid(UUID()), title: "Floating", instanceIndex: 0),
            windowID: 88,
            ownerPID: 1,
            sourcePID: 1,
            bounds: .zero,
            title: nil,
            isOnScreen: true
        )
        manager.add(anchored, to: group.id)
        #expect(manager.groupSet == before)
    }

    @Test("Renaming and collapsing a user group changes it in place")
    func renameAndCollapseUserGroup() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let members = [item("A", bundle: "com.example.one"), item("B", bundle: "com.example.two")]
        let group = try #require(manager.createGroup(name: nil, items: members))

        manager.rename(.user(group.id), to: "Tools", members: members)
        manager.setCollapsed(true, for: .user(group.id), members: members)

        let stored = try #require(manager.groupSet.group(id: group.id))
        #expect(stored.name == "Tools")
        #expect(stored.isCollapsed)
        #expect(manager.userGroupID(for: .user(group.id), members: members) == group.id)
    }

    @Test("Editing an automatic cluster turns it into a user group and suppresses the bundle")
    func automaticClusterMaterializes() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let namespace = MenuBarItemTag.Namespace.string("com.example.cluster")
        let members = [item("A", bundle: "com.example.cluster"), item("B", bundle: "com.example.cluster")]

        let automatic = manager.resolvedGroups(for: members)
        try #require(automatic.count == 1)
        #expect(automatic[0].origin == .automatic(namespace))
        #expect(manager.resolvedGroup(containing: members[1], in: members)?.memberIndices == [0, 1])

        manager.rename(.automatic(namespace), to: "Cluster", members: members)

        #expect(manager.groupSet.groups.count == 1)
        #expect(manager.groupSet.groups.first?.name == "Cluster")
        #expect(manager.groupSet.isSuppressedAutomaticNamespace(namespace))
        let resolved = manager.resolvedGroups(for: members)
        #expect(resolved.count == 1)
        #expect(resolved.first?.origin.isUserAuthored == true)
    }

    @Test("Collapsing and naming identities of automatic clusters materialize them too")
    func automaticCollapseAndIdentity() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let first = MenuBarItemTag.Namespace.string("com.example.first")
        let second = MenuBarItemTag.Namespace.string("com.example.second")
        let firstMembers = [item("A", bundle: "com.example.first"), item("B", bundle: "com.example.first")]
        let secondMembers = [item("C", bundle: "com.example.second"), item("D", bundle: "com.example.second")]

        manager.setCollapsed(true, for: .automatic(first), members: firstMembers)
        let id = try #require(manager.userGroupID(for: .automatic(second), members: secondMembers))

        #expect(manager.groupSet.groups.count == 2)
        #expect(manager.groupSet.group(id: id)?.memberIdentifiers == secondMembers.map(\.uniqueIdentifier))
        #expect(manager.groupSet.groups.contains { $0.isCollapsed })
    }

    @Test("An automatic cluster with too few members cannot be materialized")
    func automaticTooFewMembers() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let namespace = MenuBarItemTag.Namespace.string("com.example.lonely")
        let lone = [item("A", bundle: "com.example.lonely")]

        manager.rename(.automatic(namespace), to: "Nope", members: lone)
        manager.setCollapsed(true, for: .automatic(namespace), members: lone)

        #expect(manager.userGroupID(for: .automatic(namespace), members: lone) == nil)
        #expect(manager.groupSet == .empty)
    }

    @Test("Ungrouping an automatic cluster suppresses its bundle")
    func ungroupAutomatic() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let namespace = MenuBarItemTag.Namespace.string("com.example.cluster")
        let members = [item("A", bundle: "com.example.cluster"), item("B", bundle: "com.example.cluster")]

        manager.ungroup(.automatic(namespace))

        #expect(manager.groupSet.isSuppressedAutomaticNamespace(namespace))
        #expect(manager.resolvedGroups(for: members).isEmpty)
    }

    @Test("A resolved group's name comes from the user, then the members")
    func displayNameFallbacks() throws {
        let manager = try MenuBarItemGroupManager(defaults: makeDefaults())
        let members = [item("A", bundle: "com.example.names"), item("B", bundle: "com.example.names")]
        let named = ResolvedGroup(origin: .user(UUID()), displayName: "Mine", isCollapsed: false, memberIndices: [0, 1])
        let unnamed = ResolvedGroup(origin: .user(UUID()), displayName: nil, isCollapsed: false, memberIndices: [0, 1])
        let empty = ResolvedGroup(origin: .user(UUID()), displayName: nil, isCollapsed: false, memberIndices: [5, 6])

        #expect(manager.displayName(for: named, in: members) == "Mine")
        #expect(manager.displayName(for: unnamed, in: members) == members[0].autoDetectedName)
        #expect(manager.displayName(for: empty, in: members) == String(localized: "\(2) items"))

        let pid = ProcessInfo.processInfo.processIdentifier
        let owned = [item("A", pid: pid), item("B", pid: pid)]
        let ownerName = NSRunningApplication(processIdentifier: pid)?.localizedName
        #expect(manager.displayName(for: unnamed, in: owned) == ownerName)
    }

    @Test("A profile's group set replaces the current one, and nil clears it")
    func applyProfileSet() throws {
        let defaults = try makeDefaults()
        let manager = MenuBarItemGroupManager(defaults: defaults)
        var set = MenuBarItemGroupSet.empty
        _ = set.createGroup(name: "Profile", memberIdentifiers: ["com.example.a:A", "com.example.b:B"])

        manager.apply(set)
        #expect(manager.groupSet.groups.first?.name == "Profile")

        manager.apply(nil)
        #expect(manager.groupSet == .empty)
        #expect(defaults.data(forKey: storageKey) == nil)
    }

    @Test("A payload this build cannot decode is left alone and the manager starts empty")
    func undecodablePayloadIsKept() throws {
        let defaults = try makeDefaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: storageKey)

        let manager = MenuBarItemGroupManager(defaults: defaults)

        #expect(manager.groupSet == .empty)
        #expect(defaults.data(forKey: storageKey) == garbage)
    }

    @Test("A payload from a newer version is ignored but kept")
    func newerVersionIsKept() throws {
        let defaults = try makeDefaults()
        var set = MenuBarItemGroupSet.empty
        _ = set.createGroup(name: "Future", memberIdentifiers: ["com.example.a:A", "com.example.b:B"])
        set.version = MenuBarItemGroupSet.currentVersion + 1
        let data = try JSONEncoder().encode(set)
        defaults.set(data, forKey: storageKey)

        let manager = MenuBarItemGroupManager(defaults: defaults)

        #expect(manager.groupSet == .empty)
        #expect(defaults.data(forKey: storageKey) == data)
    }
}
