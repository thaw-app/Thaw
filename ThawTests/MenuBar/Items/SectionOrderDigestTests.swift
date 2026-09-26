//
//  SectionOrderDigestTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The saved-section-order digest (#885). Per-section counts could not
/// attribute that report because the fault keeps counts correct and only
/// reorders; the digest and REORDERED-ONLY marker make it readable from a log.
@Suite("Section order digest")
struct SectionOrderDigestTests {
    @Test("The digest is order-sensitive")
    func digestIsOrderSensitive() {
        let items = ["a:Item-0", "b:Item-0", "c:Item-0"]
        #expect(
            MenuBarItemManager.orderDigest(items)
                != MenuBarItemManager.orderDigest(items.reversed())
        )
    }

    /// Digests are compared across relaunches, so no per-process hash seed.
    @Test("The digest is stable for equal input")
    func digestIsStable() {
        let items = ["com.example.app:Item-0", "com.other.app:Item-1"]
        #expect(MenuBarItemManager.orderDigest(items) == MenuBarItemManager.orderDigest(items))
        #expect(MenuBarItemManager.orderDigest([]) == MenuBarItemManager.orderDigest([]))
    }

    /// Separated before hashing, so a boundary shift between entries cannot alias.
    @Test("The digest distinguishes identifier boundaries")
    func digestSeparatesIdentifiers() {
        #expect(
            MenuBarItemManager.orderDigest(["ab", "c"])
                != MenuBarItemManager.orderDigest(["a", "bc"])
        )
    }

    /// Membership intact, sequence permuted: the case counts hid (#885).
    @Test("A pure reorder is called out as REORDERED-ONLY")
    func pureReorderIsMarked() {
        let before = ["hidden": ["a", "b", "c", "d"]]
        let after = ["hidden": ["d", "c", "b", "a"]]
        let summary = MenuBarItemManager.sectionOrderChangeSummary(from: before, to: after)

        #expect(summary.contains("REORDERED-ONLY"))
        #expect(summary.contains("4/4 displaced"))
        #expect(summary.contains("hidden=4"))
    }

    /// An app launching or an item appearing must not look like the reorder fault.
    @Test("A membership change is not marked as a reorder")
    func membershipChangeIsNotMarked() {
        let before = ["hidden": ["a", "b", "c"]]
        let after = ["hidden": ["a", "b", "c", "d"]]
        let summary = MenuBarItemManager.sectionOrderChangeSummary(from: before, to: after)

        #expect(!summary.contains("REORDERED-ONLY"))
        #expect(summary.contains("hidden=3→4"))
    }

    /// Untouched sections stay quiet so the changed one is easy to find.
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

    /// 46 carried over, one added, none at its old index. It reads as a size
    /// change, but the digests still pin both sequences.
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
