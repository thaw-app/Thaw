//
//  MenuBarItemGroupResolutionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
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

    /// While the store is empty in the field, resolution must be a faithful
    /// superset of today's derivation — this is the gate for landing the
    /// resolver swap without a behaviour change.
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

    /// `LayoutBarContainer` maps its non-item arranged views (the New Items
    /// badge, opaque slots) onto a non-groupable placeholder tag before
    /// resolving. Those placeholders must never become members, and must not
    /// break the member indices of the real items around them.
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

        // The user group claims one item from each bundle, leaving each bundle
        // with a single unclaimed item — so neither automatic cluster forms.
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
        // The store is untouched — quitting an app must never destroy a group.
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

    // MARK: placeBlock

    @Test("placeBlock gathers a scattered group at the drop cursor")
    func placeBlockGathersScatteredMembers() {
        let elements = ["a1", "x", "a2", "y", "a3"]
        let result = MenuBarItemGroupResolver.placeBlock(elements, memberIndices: [0, 2, 4], toIndexInOriginal: 0)
        #expect(result == ["a1", "a2", "a3", "x", "y"])
    }

    @Test("placeBlock moves a gathered group to the end")
    func placeBlockMovesToEnd() {
        let elements = ["a1", "a2", "x", "y"]
        let result = MenuBarItemGroupResolver.placeBlock(elements, memberIndices: [0, 1], toIndexInOriginal: 4)
        #expect(result == ["x", "y", "a1", "a2"])
    }

    @Test("placeBlock preserves member order and non-member relative order")
    func placeBlockPreservesOrders() {
        let elements = ["x", "a1", "y", "a2", "z"]
        let result = MenuBarItemGroupResolver.placeBlock(elements, memberIndices: [1, 3], toIndexInOriginal: 5)
        #expect(result == ["x", "y", "z", "a1", "a2"])
    }

    @Test("placeBlock is a permutation of its input")
    func placeBlockIsAPermutation() {
        let elements = ["a1", "x", "a2", "y", "a3", "z"]
        for destination in 0 ... elements.count {
            let result = MenuBarItemGroupResolver.placeBlock(
                elements,
                memberIndices: [0, 2, 4],
                toIndexInOriginal: destination
            )
            #expect(result.sorted() == elements.sorted(), "destination \(destination) lost or invented an element")
            #expect(result.count == elements.count)
        }
    }

    @Test("placeBlock leaves an already-gathered group in place when re-applied")
    func placeBlockIsStableOnGatheredInput() {
        let elements = ["a1", "a2", "a3", "x"]
        let result = MenuBarItemGroupResolver.placeBlock(elements, memberIndices: [0, 1, 2], toIndexInOriginal: 0)
        #expect(result == elements)
    }

    @Test("placeBlock ignores out-of-range indices rather than trapping")
    func placeBlockIgnoresOutOfRange() {
        let elements = ["a", "b"]
        #expect(MenuBarItemGroupResolver.placeBlock(elements, memberIndices: [5], toIndexInOriginal: 0) == elements)
        #expect(MenuBarItemGroupResolver.placeBlock(elements, memberIndices: [], toIndexInOriginal: 0) == elements)
    }
}
