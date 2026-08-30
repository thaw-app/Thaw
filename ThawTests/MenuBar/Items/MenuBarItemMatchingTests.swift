//
//  MenuBarItemMatchingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Characterizes the `Sequence<MenuBarItem>` matching helpers, which are
/// the identity vocabulary for re-finding an item across window-list
/// snapshots.
///
/// `first(matching:)` is exact tag equality — windowID included for
/// non-system items. `first(matchingTag:pid:)` deliberately ignores
/// windowIDs, which churn between fetches, and rests identity on the tag
/// plus the effective PID (sourcePID, falling back to ownerPID). Getting
/// the fallback wrong strands rehides and click refetches, so the
/// semantics are pinned here.
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
}
