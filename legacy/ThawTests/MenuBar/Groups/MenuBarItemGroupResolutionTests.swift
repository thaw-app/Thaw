//
//  MenuBarItemGroupResolutionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar item group resolution")
struct MenuBarItemGroupResolutionTests {
    private func tag(_ bundle: String, _ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundle), title: title, windowID: nil, instanceIndex: 0)
    }

    // MARK: Regression lock

    /// With an empty store, resolution must match automatic derivation exactly.
    @Test("An empty store reproduces automatic grouping exactly")
    func emptyStoreMatchesAutomaticGrouping() {
        let tags = [
            tag("com.a", "1"),
            tag("com.b", "1"),
            tag("com.a", "2"),
            tag("com.c", "1"),
            tag("com.b", "2"),
        ]

        let automatic = MenuBarItemGrouping.groups(in: tags)
        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: .empty)

        #expect(resolved.count == automatic.count)
        for (lhs, rhs) in zip(resolved, automatic) {
            #expect(lhs.memberIndices == rhs.memberIndices)
            #expect(lhs.origin == .automatic(rhs.namespace))
            #expect(lhs.displayName == nil)
        }
    }

    @Test("No groups resolve when nothing shares a bundle")
    func singletonsDoNotGroup() {
        let tags = [tag("com.a", "1"), tag("com.b", "1"), tag("com.c", "1")]
        #expect(MenuBarItemGroupResolver.resolve(tags: tags, groupSet: .empty).isEmpty)
    }

    /// `LayoutBarContainer` maps non-item views (New Items badge, opaque slots)
    /// to a placeholder tag, which must not join or shift member indices.
    @Test("Non-groupable placeholders never join a group")
    func placeholdersNeverJoinAGroup() {
        let placeholder = MenuBarItemTag.visibleControlItem
        let tags = [
            tag("com.a", "1"),
            placeholder,
            tag("com.a", "2"),
            placeholder,
        ]

        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: .empty)

        #expect(resolved.count == 1)
        #expect(resolved[0].memberIndices == [0, 2])
        // And the placeholder-heavy shape still matches automatic derivation.
        #expect(resolved[0].memberIndices == MenuBarItemGrouping.groups(in: tags).first?.memberIndices)
    }

    // MARK: User groups

    @Test("A user group spans bundles and suppresses the automatic clusters it consumes")
    func userGroupSpansBundles() {
        let tags = [
            tag("com.a", "1"),
            tag("com.a", "2"),
            tag("com.b", "1"),
            tag("com.b", "2"),
        ]
        var set = MenuBarItemGroupSet()
        set.createGroup(name: "Work", memberIdentifiers: [tags[0].tagIdentifier, tags[2].tagIdentifier])

        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set)

        // The user group leaves each bundle one unclaimed item, so neither
        // automatic cluster forms.
        #expect(resolved.count == 1)
        #expect(resolved[0].origin.isUserAuthored)
        #expect(resolved[0].displayName == "Work")
        #expect(resolved[0].memberIndices == [0, 2])
    }

    @Test("An automatic cluster still forms from the members a user group left behind")
    func automaticClusterFormsFromRemainder() {
        let tags = [
            tag("com.a", "1"),
            tag("com.a", "2"),
            tag("com.a", "3"),
            tag("com.b", "1"),
            tag("com.b", "2"),
        ]
        var set = MenuBarItemGroupSet()
        set.createGroup(name: "Mixed", memberIdentifiers: [tags[0].tagIdentifier, tags[3].tagIdentifier])

        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set)

        #expect(resolved.count == 2)
        #expect(resolved[0].origin.isUserAuthored)
        #expect(resolved[0].memberIndices == [0, 3])
        // com.a keeps two unclaimed members, so its automatic cluster survives.
        #expect(resolved[1].origin == .automatic(.string("com.a")))
        #expect(resolved[1].memberIndices == [1, 2])
    }

    @Test("Groups are ordered left to right by their first member")
    func groupsOrderedByFirstMember() {
        let tags = [
            tag("com.b", "1"),
            tag("com.a", "1"),
            tag("com.b", "2"),
            tag("com.a", "2"),
        ]
        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: .empty)

        #expect(resolved.map(\.memberIndices.first) == [0, 1])
    }

    // MARK: Unresolvable members

    @Test("A group whose app is not running simply does not render, and is never mutated")
    func absentMembersAreOmitted() {
        let tags = [tag("com.a", "1"), tag("com.a", "2")]
        var set = MenuBarItemGroupSet()
        set.createGroup(name: "Away", memberIdentifiers: ["com.gone:One", "com.gone:Two"])

        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set)

        // Nothing of the user group is live, so only the automatic cluster shows.
        #expect(resolved.count == 1)
        #expect(resolved[0].origin == .automatic(.string("com.a")))
        // Quitting an app must never destroy a group.
        #expect(set.groups.count == 1)
    }

    @Test("A partially live group needs two resolvable members to render")
    func partiallyLiveGroupDoesNotRender() {
        let tags = [tag("com.a", "1"), tag("com.z", "1")]
        var set = MenuBarItemGroupSet()
        set.createGroup(name: "Half", memberIdentifiers: [tags[0].tagIdentifier, "com.gone:Two"])

        #expect(MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set).isEmpty)
        #expect(set.groups.count == 1)
    }

    // MARK: Groupability still governs membership

    @Test("Non-groupable items never join a user group even when stored as members")
    func nonGroupableItemsNeverJoin() {
        let control = MenuBarItemTag.visibleControlItem
        let systemModule = MenuBarItemTag(namespace: .controlCenter, title: "Clock")
        let tags = [control, systemModule, tag("com.a", "1")]

        var set = MenuBarItemGroupSet()
        set.createGroup(
            name: "Illegal",
            memberIdentifiers: [control.tagIdentifier, systemModule.tagIdentifier, tags[2].tagIdentifier]
        )

        // Only the third tag is groupable, so fewer than two members resolve.
        #expect(MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set).isEmpty)
    }

    // MARK: Suppression

    @Test("A suppressed namespace stops its automatic cluster re-forming")
    func suppressionPreventsAutomaticCluster() {
        let tags = [tag("com.a", "1"), tag("com.a", "2"), tag("com.b", "1"), tag("com.b", "2")]
        var set = MenuBarItemGroupSet()
        set.suppressAutomatic(.string("com.a"))

        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set)

        #expect(resolved.count == 1)
        #expect(resolved[0].origin == .automatic(.string("com.b")))
    }

    @Test("A user group still resolves for a suppressed bundle")
    func suppressionDoesNotBlockUserGroups() {
        let tags = [tag("com.a", "1"), tag("com.a", "2")]
        var set = MenuBarItemGroupSet()
        set.suppressAutomatic(.string("com.a"))
        set.createGroup(name: "Explicit", memberIdentifiers: [tags[0].tagIdentifier, tags[1].tagIdentifier])

        let resolved = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: set)

        #expect(resolved.count == 1)
        #expect(resolved[0].displayName == "Explicit")
    }

    // MARK: Drag units

    @Test("A member's drag unit is the whole group; a loner's is itself")
    func dragUnitCoversWholeGroup() {
        let tags = [tag("com.a", "1"), tag("com.b", "1"), tag("com.a", "2")]
        let groups = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: .empty)

        #expect(MenuBarItemGroupResolver.dragUnitIndices(forIndex: 0, in: groups) == [0, 2])
        #expect(MenuBarItemGroupResolver.dragUnitIndices(forIndex: 2, in: groups) == [0, 2])
        #expect(MenuBarItemGroupResolver.dragUnitIndices(forIndex: 1, in: groups) == [1])
    }
}
