//
//  MenuBarItemGroupingTests.swift
//  Project: Thaw
//
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
        // Grouping is by bundle, not adjacency, so A and A group across B.
        let tags = [tag("com.a", "1"), tag("com.b", "1"), tag("com.a", "2")]
        let groups = MenuBarItemGrouping.groups(in: tags)
        #expect(groups.count == 1)
        #expect(groups.first?.namespace == .string("com.a"))
        #expect(groups.first?.memberIndices == [0, 2])
    }

    @Test
    func systemItemBetweenMembersDoesNotBreakTheBundle() {
        // A non-groupable system item between two members does not split the
        // bundle, and the Clock is not a member.
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
}
