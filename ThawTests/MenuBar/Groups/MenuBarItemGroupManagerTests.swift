//
//  MenuBarItemGroupManagerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Exercises ``MenuBarItemGroupManager`` — the persistence, publishing, and
/// editing layer over the pure grouping rules — against an isolated defaults
/// suite. The process-wide store is global, hence `.serialized`.
@Suite("Menu bar item group manager")
@MainActor
struct MenuBarItemGroupManagerTests {
    private let storageKey = "MenuBarItemGroups"

    private func makeItem(_ name: String) -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.\(name)", title: name),
            windowID: CGWindowID(abs(name.hashValue % 100_000) + 100)
        )
    }

    // MARK: - Persistence

    @Test("A fresh manager starts empty and stores nothing")
    func freshManagerStartsEmpty() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            #expect(manager.groupSet == .empty)
            #expect(defaults.data(forKey: storageKey) == nil)
        }
    }

    @Test("Creating a group persists it")
    func createGroupPersists() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let created = manager.createGroup(name: "Comms", items: [makeItem("A"), makeItem("B")])

            #expect(created != nil)
            #expect(manager.groupSet.groups.count == 1)
            #expect(defaults.data(forKey: storageKey) != nil)

            // A second manager loads what the first persisted.
            let reloaded = MenuBarItemGroupManager(defaults: defaults)
            #expect(reloaded.groupSet.groups.count == 1)
            #expect(reloaded.groupSet.groups.first?.name == "Comms")
        }
    }

    @Test("A corrupt payload starts empty without deleting the stored value")
    func corruptPayloadStartsEmptyButKeepsData() throws {
        try withScratchDefaults { defaults in
            defaults.set(Data("definitely not json".utf8), forKey: storageKey)

            let manager = MenuBarItemGroupManager(defaults: defaults)

            #expect(manager.groupSet == .empty)
            #expect(defaults.data(forKey: storageKey) != nil)
        }
    }

    @Test("A payload from a future version is ignored but left untouched")
    func futureVersionIsIgnored() throws {
        try withScratchDefaults { defaults in
            let future = try JSONSerialization.data(withJSONObject: [
                "version": 99,
                "groups": [],
                "suppressedAutomaticNamespaces": [],
            ])
            defaults.set(future, forKey: storageKey)

            let manager = MenuBarItemGroupManager(defaults: defaults)

            #expect(manager.groupSet == .empty)
            #expect(defaults.data(forKey: storageKey) == future)
        }
    }

    @Test("Returning to the empty set clears the storage key")
    func emptySetClearsTheKey() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let items = [makeItem("A"), makeItem("B")]
            let group = manager.createGroup(name: nil, items: items)
            #expect(defaults.data(forKey: storageKey) != nil)

            manager.ungroup(.user(group!.id))
            #expect(manager.groupSet == .empty)
            #expect(defaults.data(forKey: storageKey) == nil)
        }
    }

    // MARK: - Editing

    @Test("Creating a group from too few groupable items is refused")
    func createGroupRefusesUngroupableItems() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)

            #expect(manager.createGroup(name: nil, items: [makeItem("A")]) == nil)
            #expect(manager.createGroup(name: nil, items: []) == nil)
            #expect(manager.groupSet == .empty)
        }
    }

    @Test("Adding and removing members updates the persisted group")
    func addAndRemoveMembers() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let a = makeItem("A")
            let b = makeItem("B")
            let group = manager.createGroup(name: nil, items: [a, b])
            let id = group!.id

            let c = makeItem("C")
            manager.add(c, to: id)
            #expect(manager.snapshot().groups.first?.memberIdentifiers.contains(c.uniqueIdentifier) == true)

            manager.removeMember(c)
            #expect(manager.snapshot().groups.first?.memberIdentifiers.contains(c.uniqueIdentifier) == false)

            // Removing a member by identifier works without a live item, too —
            // and a group that drops below two members dissolves entirely.
            manager.removeMemberIdentifier(b.uniqueIdentifier)
            #expect(manager.snapshot().groups.isEmpty)
        }
    }

    @Test("Dissolving an automatic cluster records a suppression")
    func ungroupingAutomaticSuppressesTheNamespace() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let namespace = MenuBarItemTag.Namespace.string("com.example.slack")

            manager.ungroup(.automatic(namespace))

            let snapshot = manager.snapshot()
            #expect(snapshot.groups.isEmpty)
            #expect(snapshot.suppressedAutomaticNamespaces.contains(namespace.description))
            #expect(defaults.data(forKey: storageKey) != nil)
        }
    }

    @Test("Renaming an automatic cluster materializes a user group")
    func renamingAutomaticMaterializes() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let namespace = MenuBarItemTag.Namespace.string("com.example.slack")
            let members = [makeItem("A"), makeItem("B")]

            manager.rename(.automatic(namespace), to: "Slack", members: members)

            let snapshot = manager.snapshot()
            #expect(snapshot.groups.count == 1)
            #expect(snapshot.groups.first?.name == "Slack")
            #expect(snapshot.suppressedAutomaticNamespaces.contains(namespace.description))
        }
    }

    @Test("Renaming with too few groupable members leaves the set alone")
    func renamingAutomaticWithTooFewMembersIsRefused() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let namespace = MenuBarItemTag.Namespace.string("com.example.solo")

            manager.rename(.automatic(namespace), to: "Solo", members: [makeItem("A")])

            #expect(manager.groupSet == .empty)
        }
    }

    @Test("Collapse state persists for a user group")
    func setCollapsedPersists() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            let group = manager.createGroup(name: nil, items: [makeItem("A"), makeItem("B")])
            let id = group!.id

            manager.setCollapsed(true, for: .user(id), members: [])
            #expect(manager.snapshot().groups.first?.isCollapsed == true)

            let reloaded = MenuBarItemGroupManager(defaults: defaults)
            #expect(reloaded.snapshot().groups.first?.isCollapsed == true)
        }
    }

    // MARK: - Profiles

    @Test("Snapshot and apply round-trip the group set")
    func snapshotAndApply() throws {
        try withScratchDefaults { defaults in
            let manager = MenuBarItemGroupManager(defaults: defaults)
            manager.createGroup(name: "Exported", items: [makeItem("A"), makeItem("B")])
            let snapshot = manager.snapshot()

            let other = MenuBarItemGroupManager(defaults: defaults)
            other.apply(snapshot)
            #expect(other.snapshot() == snapshot)

            // Applying nil resets to empty.
            other.apply(nil)
            #expect(other.snapshot() == .empty)
        }
    }
}
