//
//  MenuBarItemGroupingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Menu bar item grouping")
struct MenuBarItemGroupingTests {
    private func tag(_ bundle: String, _ title: String, instance: Int = 0) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundle), title: title, windowID: nil, instanceIndex: instance)
    }

    // MARK: Groupability

    @Test
    func thirdPartyItemsAreGroupable() {
        #expect(MenuBarItemGrouping.isGroupable(tag("com.example.app", "Item-0")))
    }

    @Test
    func systemAndThawItemsAreNotGroupable() {
        // Every MenuBarAgent module shares one namespace — must never group.
        // Thaw's own control item.
        #expect(!MenuBarItemGrouping.isGroupable(MenuBarItemTag.visibleControlItem))
        // UUID / clone namespaces are not bundle strings.
        #expect(!MenuBarItemGrouping.isGroupable(MenuBarItemTag(namespace: .uuid(.init()), title: "x")))
    }

    // MARK: Group detection

    @Test
    func detectsContiguousSameBundleRun() {
        let tags = [
            tag("com.a", "1"),
            tag("com.a", "2"),
            tag("com.a", "3"),
            tag("com.b", "1"),
        ]
        let groups = MenuBarItemGrouping.groups(in: tags)
        #expect(groups.count == 1)
        #expect(groups.first?.namespace == .string("com.a"))
        #expect(groups.first?.memberIndices == [0, 1, 2])
        #expect(groups.first?.range == 0 ..< 3)
    }

    @Test
    func singleItemBundlesDoNotFormGroups() {
        let tags = [tag("com.a", "1"), tag("com.b", "1"), tag("com.c", "1")]
        #expect(MenuBarItemGrouping.groups(in: tags).isEmpty)
    }

    @Test
    func nonContiguousSameBundleItemsGroupByBundle() {
        // Grouping is by bundle, not adjacency: A and A group across B so the
        // whole bundle can be gathered and moved together.
        let tags = [tag("com.a", "1"), tag("com.b", "1"), tag("com.a", "2")]
        let groups = MenuBarItemGrouping.groups(in: tags)
        #expect(groups.count == 1)
        #expect(groups.first?.namespace == .string("com.a"))
        #expect(groups.first?.memberIndices == [0, 2])
    }

    @Test
    func systemItemBetweenMembersDoesNotBreakTheBundle() {
        // A non-groupable system item between two members does not split the
        // bundle — the two A's still form one group (and the Clock is not a member).
        let tags = [
            tag("com.a", "1"),
            MenuBarItemTag(namespace: .controlCenter, title: "Clock"),
            tag("com.a", "2"),
        ]
        let groups = MenuBarItemGrouping.groups(in: tags)
        #expect(groups.count == 1)
        #expect(groups.first?.memberIndices == [0, 2])
    }

    @Test
    func detectsMultipleGroups() {
        let tags = [
            tag("com.a", "1"), tag("com.a", "2"),
            tag("com.b", "1"),
            tag("com.c", "1"), tag("com.c", "2"), tag("com.c", "3"),
        ]
        let groups = MenuBarItemGrouping.groups(in: tags)
        #expect(groups.count == 2)
        #expect(groups[0].memberIndices == [0, 1])
        #expect(groups[1].memberIndices == [3, 4, 5])
    }

    @Test
    func groupsOrderedByFirstMember() {
        // B's first member precedes A's first member, so B's group comes first.
        let tags = [
            tag("com.b", "1"),
            tag("com.a", "1"),
            tag("com.b", "2"),
            tag("com.a", "2"),
        ]
        let groups = MenuBarItemGrouping.groups(in: tags)
        #expect(groups.count == 2)
        #expect(groups[0].namespace == .string("com.b"))
        #expect(groups[0].memberIndices == [0, 2])
        #expect(groups[1].namespace == .string("com.a"))
        #expect(groups[1].memberIndices == [1, 3])
    }

    @Test
    func groupContainingIndexResolvesMembership() {
        let tags = [tag("com.a", "1"), tag("com.a", "2"), tag("com.b", "1")]
        #expect(MenuBarItemGrouping.group(containing: 1, in: tags)?.memberIndices == [0, 1])
        #expect(MenuBarItemGrouping.group(containing: 2, in: tags) == nil)
    }

    // MARK: Block move

    @Test
    func moveBlockForward() {
        // [A1 A2 X Y] move the A-block (0..2) to sit at original index 4 (end).
        let moved = MenuBarItemGrouping.moveBlock(
            ["A1", "A2", "X", "Y"],
            sourceRange: 0 ..< 2,
            toIndexInOriginal: 4
        )
        #expect(moved == ["X", "Y", "A1", "A2"])
    }

    @Test
    func moveBlockBackward() {
        // [X Y A1 A2] move the A-block (2..4) to original index 0 (front).
        let moved = MenuBarItemGrouping.moveBlock(
            ["X", "Y", "A1", "A2"],
            sourceRange: 2 ..< 4,
            toIndexInOriginal: 0
        )
        #expect(moved == ["A1", "A2", "X", "Y"])
    }

    @Test
    func moveBlockIntoMiddle() {
        // [A1 A2 X Y Z] move A-block to original index 3 (between Y and Z... in
        // original space, index 3 is Y): lands before Y's original neighbor.
        let moved = MenuBarItemGrouping.moveBlock(
            ["A1", "A2", "X", "Y", "Z"],
            sourceRange: 0 ..< 2,
            toIndexInOriginal: 3
        )
        #expect(moved == ["X", "A1", "A2", "Y", "Z"])
    }

    @Test
    func moveBlockToSamePositionIsIdentity() {
        let original = ["X", "A1", "A2", "Y"]
        let moved = MenuBarItemGrouping.moveBlock(
            original,
            sourceRange: 1 ..< 3,
            toIndexInOriginal: 1
        )
        #expect(moved == original)
    }
}
