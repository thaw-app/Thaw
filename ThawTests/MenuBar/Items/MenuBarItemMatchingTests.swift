//
//  MenuBarItemMatchingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Builds a tag for a fictional app's status item.
private func fixtureTag(_ title: String, windowID: CGWindowID? = nil) -> MenuBarItemTag {
    .appItem(bundleID: "com.example.Fixture", title: title, windowID: windowID)
}

/// Builds an item whose tag carries no window identifier, so the item's own
/// window identifier can vary without changing tag equality.
private func fixtureItem(_ title: String, windowID: CGWindowID) -> MenuBarItem {
    .fixture(tag: fixtureTag(title), windowID: windowID)
}

/// Covers the `Sequence<MenuBarItem>` helpers for re-finding an item across
/// window-list snapshots.
///
/// `first(matching:)` is exact tag equality, windowID included for non-system
/// items. `first(matchingTag:pid:)` ignores windowIDs, which churn, and uses
/// the tag plus sourcePID, falling back to ownerPID. A wrong fallback strands
/// rehides and click refetches.
@Suite("Menu bar item matching helpers")
struct MenuBarItemMatchingTests {
    private func item(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        windowID: CGWindowID,
        instanceIndex: Int = 0,
        ownerPID: pid_t = 2559,
        sourcePID: pid_t? = nil
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: namespace,
                title: title,
                windowID: windowID,
                instanceIndex: instanceIndex
            ),
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: sourcePID,
            bounds: .zero,
            title: title,
            isOnScreen: true
        )
    }

    // MARK: - Exact tag matching

    @Test("first(matching:) requires the windowID for a non-system item")
    func exactMatchRequiresWindowID() {
        let stored = item(namespace: .string("io.tailscale.ipn.macos"), title: "Item-0", windowID: 100)
        let refetched = item(namespace: .string("io.tailscale.ipn.macos"), title: "Item-0", windowID: 200)

        #expect([refetched].first(matching: stored.tag) == nil)
        #expect([stored].first(matching: stored.tag) != nil)
    }

    @Test("removeFirst(matching:) removes exactly the matched item")
    func removeFirstRemovesMatchedItem() {
        let first = item(namespace: .string("com.a"), title: "One", windowID: 1)
        let second = item(namespace: .string("com.b"), title: "Two", windowID: 2)
        var items = [first, second]

        let removed = items.removeFirst(matching: second.tag)

        #expect(removed?.tag == second.tag)
        #expect(items.count == 1)
        #expect(items.firstIndex(matching: first.tag) == 0)
    }

    // MARK: - Tag-plus-PID matching

    @Test("first(matchingTag:pid:) finds the item across a windowID change")
    func tagAndPIDMatchIgnoresWindowID() {
        let stored = item(namespace: .string("com.a"), title: "One", windowID: 1, sourcePID: 501)
        let refetched = item(namespace: .string("com.a"), title: "One", windowID: 9, sourcePID: 501)

        let found = [refetched].first(matchingTag: stored.tag, pid: stored.sourcePID ?? stored.ownerPID)

        #expect(found?.windowID == 9)
    }

    @Test("The effective PID falls back to the owner when no source resolved")
    func effectivePIDFallsBackToOwner() {
        let unresolved = item(namespace: .controlCenter, title: "Item-0", windowID: 1, ownerPID: 2559, sourcePID: nil)

        #expect([unresolved].first(matchingTag: unresolved.tag, pid: 2559) != nil)
        #expect([unresolved].first(matchingTag: unresolved.tag, pid: 501) == nil)
    }

    @Test("A resolved sourcePID outranks the owner in the comparison")
    func sourcePIDOutranksOwner() {
        let resolved = item(namespace: .string("com.a"), title: "One", windowID: 1, ownerPID: 2559, sourcePID: 501)

        #expect([resolved].first(matchingTag: resolved.tag, pid: 501) != nil)
        #expect([resolved].first(matchingTag: resolved.tag, pid: 2559) == nil)
    }

    @Test("A sibling with a different instance index does not match")
    func differentInstanceIndexDoesNotMatch() {
        let third = item(namespace: .controlCenter, title: "Item-0", windowID: 1, instanceIndex: 3)
        let fifth = item(namespace: .controlCenter, title: "Item-0", windowID: 1, instanceIndex: 5)

        #expect([fifth].first(matchingTag: third.tag, pid: 2559) == nil)
    }

    // MARK: - Lookup by tag

    /// The three lookup helpers are one-liners, but they are the only place
    /// item lookup is expressed, and every caller depends on two things the
    /// implementation does not spell out: the returned index is a real
    /// collection index (so it survives slicing), and matching goes through
    /// `MenuBarItemTag` equality rather than window identity.
    @MainActor
    @Suite("Menu bar item lookup")
    struct MenuBarItemLookupTests {
        private let items = [
            fixtureItem("Alpha", windowID: 1),
            fixtureItem("Beta", windowID: 2),
            fixtureItem("Alpha", windowID: 3),
        ]

        @Test("An empty collection matches nothing")
        func emptyCollectionMatchesNothing() {
            let empty = [MenuBarItem]()

            #expect(empty.firstIndex(matching: fixtureTag("Alpha")) == nil)
            #expect(empty.first(matching: fixtureTag("Alpha")) == nil)
        }

        @Test("An absent tag matches nothing")
        func absentTagMatchesNothing() {
            #expect(items.firstIndex(matching: fixtureTag("Gamma")) == nil)
            #expect(items.first(matching: fixtureTag("Gamma")) == nil)
        }

        @Test("A repeated tag resolves to the earliest element")
        func repeatedTagResolvesToEarliest() throws {
            #expect(items.firstIndex(matching: fixtureTag("Alpha")) == 0)

            let found = try #require(items.first(matching: fixtureTag("Alpha")))
            #expect(found.windowID == 1)
        }

        /// The index has to be usable to subscript the collection it came
        /// from, which rules out anything offset-based.
        @Test("A slice reports an index valid in the slice")
        func sliceReportsUsableIndex() throws {
            let slice = items[1...]

            let index = try #require(slice.firstIndex(matching: fixtureTag("Alpha")))
            #expect(index == 2)
            #expect(slice[index].windowID == 3)
        }

        /// Two items from the same app with the same title but different tag
        /// window identifiers are different items, and lookup must not conflate
        /// them.
        @Test("Tags that differ only by window identifier do not match")
        func windowIDDistinguishesTags() {
            let collection = [MenuBarItem.fixture(tag: fixtureTag("Alpha", windowID: 10), windowID: 10)]

            #expect(collection.firstIndex(matching: fixtureTag("Alpha", windowID: 10)) == 0)
            #expect(collection.firstIndex(matching: fixtureTag("Alpha", windowID: 11)) == nil)
        }

        // `removeFirst(matching:)` is mutating, and the #expect/#require macros
        // capture their argument into a closure that binds it immutably. Each
        // call is therefore made on its own line and the result inspected after.

        @Test("removeFirst takes one occurrence and leaves the rest")
        func removeFirstTakesOneOccurrence() throws {
            var collection = items

            let removedItem = collection.removeFirst(matching: fixtureTag("Alpha"))
            let removed = try #require(removedItem)

            #expect(removed.windowID == 1)
            #expect(collection.map(\.windowID) == [2, 3])
        }

        @Test("removeFirst leaves the collection alone when nothing matches")
        func removeFirstWithoutMatchIsANoOp() {
            var collection = items

            let removed = collection.removeFirst(matching: fixtureTag("Gamma"))

            #expect(removed == nil)
            #expect(collection.map(\.windowID) == [1, 2, 3])
        }

        @Test("removeFirst on an empty collection returns nil")
        func removeFirstOnEmptyCollection() {
            var collection = [MenuBarItem]()

            let removed = collection.removeFirst(matching: fixtureTag("Alpha"))

            #expect(removed == nil)
            #expect(collection.isEmpty)
        }
    }
}
