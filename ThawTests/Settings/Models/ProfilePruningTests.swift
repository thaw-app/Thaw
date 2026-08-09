//
//  ProfilePruningTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers the pruning a profile's layout gets on the way out.
///
/// A profile is captured from the live bar, so a capture taken while
/// source-PID resolution was degraded bakes in identifiers that can never
/// match a live item again. `MenuBarItemManager` already prunes the saved
/// section order when it loads it (#788, #815), but nothing rewrote a
/// profile — #881's reporter carried one holding four Control-Center-hosted
/// entries with no title at all, and every apply planned against them.
@Suite("Profile layout pruning")
struct ProfilePruningTests {
    /// The unidentifiable entries from #881's `547c9ba` log, as they appear
    /// in `uniqueIdentifier` form.
    private static let untitledControlCenterEntries = [
        "com.apple.controlcenter:",
        "com.apple.controlcenter::1",
        "com.apple.controlcenter::2",
        "com.apple.controlcenter::3",
    ]

    private func layout(
        itemOrder: [String: [String]]? = nil,
        savedSectionOrder: [String: [String]] = [:]
    ) -> MenuBarLayoutSnapshot {
        MenuBarLayoutSnapshot(
            savedSectionOrder: savedSectionOrder,
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemOrder: itemOrder
        )
    }

    // MARK: - Untitled Control Center entries

    @Test("An untitled Control Center entry is dropped from itemOrder")
    func untitledEntryIsDroppedFromItemOrder() {
        let snapshot = layout(itemOrder: [
            "visible": Self.untitledControlCenterEntries + ["eu.exelban.Stats:CPU_bar_chart"],
        ])
        #expect(snapshot.resolvedItemOrder["visible"] == ["eu.exelban.Stats:CPU_bar_chart"])
    }

    /// Legacy profiles carry the layout in `savedSectionOrder`; they get the
    /// same treatment rather than being trusted because of their age.
    @Test("An untitled entry is dropped from a legacy savedSectionOrder")
    func untitledEntryIsDroppedFromLegacyOrder() {
        let snapshot = layout(savedSectionOrder: [
            "hidden": ["com.apple.controlcenter::2", "org.p0deje.Maccy:Item-0"],
        ])
        #expect(snapshot.resolvedItemOrder["hidden"] == ["org.p0deje.Maccy:Item-0"])
    }

    /// The section map is derived from the order, so it inherits the pruning
    /// and cannot reintroduce a dead identifier.
    @Test("The derived section map inherits the pruning")
    func derivedSectionMapInheritsThePruning() {
        let snapshot = layout(itemOrder: [
            "visible": ["com.apple.controlcenter:", "org.p0deje.Maccy:Item-0"],
        ])
        let map = snapshot.resolvedItemSectionMap
        #expect(map["org.p0deje.Maccy:Item-0"] == "visible")
        #expect(map["com.apple.controlcenter:"] == nil)
    }

    // MARK: - What must survive

    /// A titled Control Center item is a real item — Wi-Fi, Clock, BentoBox —
    /// and is only ever dropped when a real owner claims the same title.
    @Test("A titled Control Center entry survives")
    func titledControlCenterEntrySurvives() {
        let snapshot = layout(itemOrder: [
            "visible": ["com.apple.controlcenter:WiFi", "com.apple.controlcenter:Clock"],
        ])
        #expect(snapshot.resolvedItemOrder["visible"] == [
            "com.apple.controlcenter:WiFi",
            "com.apple.controlcenter:Clock",
        ])
    }

    /// The empty-title rule is scoped to the Control Center namespace. Under a
    /// real owner an empty title still feeds planLeftmostRelocation's
    /// namespace fallback, so dropping it would remove a working remedy.
    @Test("An untitled entry under a real owner survives")
    func untitledEntryUnderRealOwnerSurvives() {
        let snapshot = layout(itemOrder: ["visible": ["com.shortcutlabs.FlicMac:"]])
        #expect(snapshot.resolvedItemOrder["visible"] == ["com.shortcutlabs.FlicMac:"])
    }

    /// Pruning drops entries; it must never reorder the ones it keeps (#885).
    @Test("Order is preserved among surviving entries")
    func orderIsPreservedAmongSurvivors() {
        let kept = [
            "eu.exelban.Stats:CPU_bar_chart",
            "org.p0deje.Maccy:Item-0",
            "com.tunabellysoftware.tgpro:Item-0",
        ]
        let snapshot = layout(itemOrder: [
            "visible": [kept[0], "com.apple.controlcenter::1", kept[1], "com.apple.controlcenter:", kept[2]],
        ])
        #expect(snapshot.resolvedItemOrder["visible"] == kept)
    }

    /// An empty profile stays empty rather than acquiring sections.
    @Test("An empty layout resolves to an empty order")
    func emptyLayoutResolvesEmpty() {
        #expect(layout().resolvedItemOrder.isEmpty)
    }
}

/// The `LayoutSolver` rule the profile pruning above leans on.
@Suite("Untitled entry pruning")
struct UntitledEntryPruningTests {
    @Test("An untitled Control Center entry is pruned")
    func untitledControlCenterEntryIsPruned() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["com.apple.controlcenter:", "org.p0deje.Maccy:Item-0"],
        ])
        #expect(pruned["visible"] == ["org.p0deje.Maccy:Item-0"])
    }

    /// The instance-index suffix is not a title: `com.apple.controlcenter::2`
    /// is the third untitled item, not an item called ":2".
    @Test("An untitled entry with an instance index is pruned")
    func untitledEntryWithInstanceIndexIsPruned() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["com.apple.controlcenter::2", "org.p0deje.Maccy:Item-0"],
        ])
        #expect(pruned["visible"] == ["org.p0deje.Maccy:Item-0"])
    }

    /// A numeric title is a title. Only the empty one between two colons is
    /// the unidentifiable shape.
    @Test("A Control Center entry titled with digits survives")
    func numericallyTitledEntrySurvives() {
        let pruned = LayoutSolver.prunedSectionOrder(["visible": ["com.apple.controlcenter:2"]])
        #expect(pruned["visible"] == ["com.apple.controlcenter:2"])
    }

    /// The pre-existing #788 rule still applies alongside the new one.
    @Test("A provisional duplicate is still pruned")
    func provisionalDuplicateIsStillPruned() {
        let pruned = LayoutSolver.prunedSectionOrder([
            "visible": ["com.apple.controlcenter:Item-0", "com.shortcutlabs.FlicMac:Item-0"],
        ])
        #expect(pruned["visible"] == ["com.shortcutlabs.FlicMac:Item-0"])
    }
}
