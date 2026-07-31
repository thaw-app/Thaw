//
//  MenuBarItemGroupManagerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Persistence and editing behaviour of the app-side group store. Uses an
/// isolated `UserDefaults` suite so these never touch the real preferences —
/// the test host *is* the Thaw app.
@MainActor
struct MenuBarItemGroupManagerTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "com.stonerl.Thaw.tests.groups.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("could not create an isolated defaults suite")
        }
        return defaults
    }

    private func item(_ bundle: String, _ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundle, title: title),
            windowID: windowID,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 22)
        )
    }

    private var pair: [MenuBarItem] {
        [item("com.a", "One", windowID: 1), item("com.b", "Two", windowID: 2)]
    }

    // MARK: Defaults round-trip

    @Test("An absent key means no groups, identical to before the feature")
    func absentKeyMeansEmpty() {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        #expect(manager.groupSet == .empty)
    }

    @Test("Groups survive a store reload")
    func groupsRoundTripThroughDefaults() throws {
        let defaults = makeDefaults()
        let manager = MenuBarItemGroupManager(defaults: defaults)
        let created = try #require(manager.createGroup(name: "Work", items: pair))

        let reloaded = MenuBarItemGroupManager(defaults: defaults)

        #expect(reloaded.groupSet.groups.count == 1)
        #expect(reloaded.groupSet.groups.first?.id == created.id)
        #expect(reloaded.groupSet.groups.first?.name == "Work")
    }

    @Test("An empty set clears the key rather than storing an empty document")
    func emptySetClearsTheKey() throws {
        let defaults = makeDefaults()
        let manager = MenuBarItemGroupManager(defaults: defaults)
        let created = try #require(manager.createGroup(name: "Work", items: pair))
        #expect(defaults.data(forKey: Defaults.Key.menuBarItemGroups.rawValue) != nil)

        manager.ungroup(.user(created.id))

        #expect(defaults.data(forKey: Defaults.Key.menuBarItemGroups.rawValue) == nil)
    }

    /// Deleting the key on a decode failure would destroy a user's groups the
    /// moment a future build wrote something this one cannot read.
    @Test("Undecodable stored data is left on disk, not deleted")
    func undecodableDataIsPreserved() {
        let defaults = makeDefaults()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: Defaults.Key.menuBarItemGroups.rawValue)

        let manager = MenuBarItemGroupManager(defaults: defaults)

        #expect(manager.groupSet == .empty)
        #expect(defaults.data(forKey: Defaults.Key.menuBarItemGroups.rawValue) == garbage)
    }

    @Test("A newer store version is ignored without rewriting it")
    func newerVersionIsIgnoredAndPreserved() {
        let defaults = makeDefaults()
        let future = Data(
            #"{"version":999,"groups":[],"suppressedAutomaticNamespaces":["com.a"]}"#.utf8
        )
        defaults.set(future, forKey: Defaults.Key.menuBarItemGroups.rawValue)

        let manager = MenuBarItemGroupManager(defaults: defaults)

        #expect(manager.groupSet == .empty)
        #expect(defaults.data(forKey: Defaults.Key.menuBarItemGroups.rawValue) == future)
    }

    // MARK: Editing

    @Test("A group needs two groupable items")
    func createRequiresTwoGroupableItems() {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())

        #expect(manager.createGroup(name: nil, items: [item("com.a", "One", windowID: 1)]) == nil)
        // Thaw's own control item is never groupable, so this is a one-item group.
        let withControl = [
            item("com.a", "One", windowID: 1),
            MenuBarItem.fixture(tag: .visibleControlItem, windowID: 9),
        ]
        #expect(manager.createGroup(name: nil, items: withControl) == nil)
        #expect(manager.groupSet.groups.isEmpty)
    }

    @Test("Ungrouping an automatic cluster suppresses it so it cannot re-derive")
    func ungroupingAutomaticSuppressesTheNamespace() {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())

        manager.ungroup(.automatic(.string("com.a")))

        #expect(manager.groupSet.isSuppressedAutomaticNamespace(.string("com.a")))
        #expect(manager.groupSet.groups.isEmpty)
    }

    /// Editing an automatic cluster has to turn it into a real record, or the
    /// edit is lost on the next layout pass when the cluster re-derives.
    @Test("Renaming an automatic cluster materializes it into a user group")
    func renamingAutomaticMaterializes() {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        let members = [item("com.a", "One", windowID: 1), item("com.a", "Two", windowID: 2)]

        manager.rename(.automatic(.string("com.a")), to: "Monitors", members: members)

        #expect(manager.groupSet.groups.count == 1)
        #expect(manager.groupSet.groups.first?.name == "Monitors")
        // Both must hold, or the user group and the automatic cluster would
        // resolve at the same time.
        #expect(manager.groupSet.isSuppressedAutomaticNamespace(.string("com.a")))
    }

    @Test("Collapsing an automatic cluster also materializes it")
    func collapsingAutomaticMaterializes() {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        let members = [item("com.a", "One", windowID: 1), item("com.a", "Two", windowID: 2)]

        manager.setCollapsed(true, for: .automatic(.string("com.a")), members: members)

        #expect(manager.groupSet.groups.first?.isCollapsed == true)
        #expect(manager.groupSet.isSuppressedAutomaticNamespace(.string("com.a")))
    }

    @Test("Non-groupable items are refused rather than silently stored")
    func nonGroupableItemsAreRefused() throws {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        let created = try #require(manager.createGroup(name: nil, items: pair))

        manager.add(MenuBarItem.fixture(tag: .visibleControlItem, windowID: 9), to: created.id)

        #expect(manager.groupSet.groups.first?.memberIdentifiers.count == 2)
    }

    // MARK: Resolution helpers

    @Test("A member's drag unit is the whole group, in section order")
    func dragUnitCoversTheGroup() {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        let first = item("com.a", "One", windowID: 1)
        let other = item("com.z", "Z", windowID: 2)
        let second = item("com.a", "Two", windowID: 3)
        let items = [first, other, second]

        let unit = manager.dragUnit(for: first, in: items)

        #expect(unit.map(\.uniqueIdentifier) == [first.uniqueIdentifier, second.uniqueIdentifier])
        #expect(manager.dragUnit(for: other, in: items).map(\.uniqueIdentifier) == [other.uniqueIdentifier])
    }

    /// The cross-section drop path (`crossSectionGroupMembers`) resolves through
    /// this, so a user group spanning two bundles must travel as one unit — the
    /// behaviour the old bundle-only derivation could not express.
    @Test("A cross-bundle user group resolves for any of its members")
    func crossBundleGroupResolvesForEachMember() throws {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        let first = item("com.a", "One", windowID: 1)
        let stranger = item("com.z", "Z", windowID: 2)
        let second = item("com.b", "Two", windowID: 3)
        let items = [first, stranger, second]
        try #require(manager.createGroup(name: "Work", items: [first, second]))

        let viaFirst = try #require(manager.resolvedGroup(containing: first, in: items))
        let viaSecond = try #require(manager.resolvedGroup(containing: second, in: items))

        #expect(viaFirst == viaSecond)
        #expect(viaFirst.memberIndices == [0, 2])
        #expect(viaFirst.displayName == "Work")
        // An item outside the group must not be dragged along.
        #expect(manager.resolvedGroup(containing: stranger, in: items) == nil)
    }

    @Test("A named group uses its name; an unnamed one derives one")
    func displayNameFallsBackToTheApp() throws {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        let items = [item("com.a", "One", windowID: 1), item("com.a", "Two", windowID: 2)]
        manager.rename(.automatic(.string("com.a")), to: "Monitors", members: items)

        let group = try #require(manager.resolvedGroups(for: items).first)
        #expect(manager.displayName(for: group, in: items) == "Monitors")
    }

    // MARK: Profiles

    @Test("Applying a profile's groups replaces the current set wholesale")
    func applyReplacesGroups() throws {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        try #require(manager.createGroup(name: "Old", items: pair))

        var incoming = MenuBarItemGroupSet()
        incoming.createGroup(name: "New", memberIdentifiers: ["com.x:One", "com.y:Two"])
        manager.apply(incoming)

        #expect(manager.groupSet.groups.count == 1)
        #expect(manager.groupSet.groups.first?.name == "New")
    }

    @Test("A profile with no groups clears them")
    func applyingNilClearsGroups() throws {
        let manager = MenuBarItemGroupManager(defaults: makeDefaults())
        try #require(manager.createGroup(name: "Old", items: pair))

        manager.apply(nil)

        #expect(manager.groupSet == .empty)
    }
}
