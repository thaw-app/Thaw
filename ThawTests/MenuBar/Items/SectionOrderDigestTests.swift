//
//  SectionOrderDigestTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the saved-section-order digest added for #885.
///
/// That report could not be attributed because the only thing logged about
/// the saved order was its per-section counts, and the fault leaves counts
/// correct: the hidden section held the right 47 items, and every one of the
/// 46 carried over sat at a new index. The digest and the REORDERED-ONLY
/// marker exist so the next occurrence is readable straight off a field log.
@Suite("Section order digest")
struct SectionOrderDigestTests {
    /// The whole point: same items, different sequence, different digest.
    @Test("The digest is order-sensitive")
    func digestIsOrderSensitive() {
        let items = ["a:Item-0", "b:Item-0", "c:Item-0"]
        #expect(
            MenuBarItemManager.orderDigest(items)
                != MenuBarItemManager.orderDigest(items.reversed())
        )
    }

    /// Comparing digests across relaunches is the entire use case, so the
    /// value must not depend on a per-process hash seed.
    @Test("The digest is stable for equal input")
    func digestIsStable() {
        let items = ["com.example.app:Item-0", "com.other.app:Item-1"]
        #expect(MenuBarItemManager.orderDigest(items) == MenuBarItemManager.orderDigest(items))
        #expect(MenuBarItemManager.orderDigest([]) == MenuBarItemManager.orderDigest([]))
    }

    /// Identifiers are separated before hashing, so a boundary shift between
    /// adjacent entries cannot alias to the same digest.
    @Test("The digest distinguishes identifier boundaries")
    func digestSeparatesIdentifiers() {
        #expect(
            MenuBarItemManager.orderDigest(["ab", "c"])
                != MenuBarItemManager.orderDigest(["a", "bc"])
        )
    }

    /// #885's signature: membership intact, sequence permuted. This is the
    /// case the counts hid, so it gets its own marker.
    @Test("A pure reorder is called out as REORDERED-ONLY")
    func pureReorderIsMarked() {
        let before = ["hidden": ["a", "b", "c", "d"]]
        let after = ["hidden": ["d", "c", "b", "a"]]
        let summary = MenuBarItemManager.sectionOrderChangeSummary(from: before, to: after)

        #expect(summary.contains("REORDERED-ONLY"))
        #expect(summary.contains("4/4 displaced"))
        #expect(summary.contains("hidden=4"))
    }

    /// A membership change is an ordinary event — an app launched, an item
    /// appeared — and must not be dressed up as the fault above.
    @Test("A membership change is not marked as a reorder")
    func membershipChangeIsNotMarked() {
        let before = ["hidden": ["a", "b", "c"]]
        let after = ["hidden": ["a", "b", "c", "d"]]
        let summary = MenuBarItemManager.sectionOrderChangeSummary(from: before, to: after)

        #expect(!summary.contains("REORDERED-ONLY"))
        #expect(summary.contains("hidden=3→4"))
    }

    /// Untouched sections stay quiet so the changed one is easy to find; the
    /// #885 apply left visible and alwaysHidden alone.
    @Test("Unchanged sections are reported as unchanged")
    func unchangedSectionsAreQuiet() {
        let order = [
            "visible": ["v1", "v2"],
            "hidden": ["h1", "h2"],
            "alwaysHidden": ["a1"],
        ]
        var changed = order
        changed["hidden"] = ["h2", "h1"]

        let summary = MenuBarItemManager.sectionOrderChangeSummary(from: order, to: changed)
        #expect(summary.contains("visible=2 unchanged"))
        #expect(summary.contains("alwaysHidden=1 unchanged"))
        #expect(summary.contains("hidden=2 REORDERED-ONLY"))
    }

    /// The reporter's shape: 46 carried over, one added, and not one of the
    /// 46 in its old position. Membership grew, so this reads as a size
    /// change — but the digests still pin the sequence on both sides, which
    /// is what makes the next occurrence attributable.
    @Test("The reporter's shape is distinguishable in one line")
    func reporterShapeIsReadable() {
        let before = (0 ..< 46).map { "app\($0):Item-0" }
        let after = Array(before.reversed()) + ["com.FluidApp.app:Item-0:1"]

        let summary = MenuBarItemManager.sectionOrderChangeSummary(
            from: ["hidden": before],
            to: ["hidden": Array(after)]
        )
        #expect(summary.contains("hidden=46→47"))
        #expect(
            MenuBarItemManager.orderDigest(before)
                != MenuBarItemManager.orderDigest(Array(after))
        )
    }
}
