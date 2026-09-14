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

/// On a non-English-locale machine, Control Center's localized owner name
/// ("Control Centre", "Kontrollzentrum") can land in the namespace when
/// bundle-ID resolution fails transiently, minting ghosts like
/// `Control Centre:Item-0:13`. The generic `Item-N` title is shared by every
/// owner, so the existing claimed-title rule skips them and they persist
/// forever, duplicating the canonical `com.apple.controlcenter:Item-N`
/// entries and inflating the stale-identifier ledger's unmatched count.
/// When the canonical `com.apple.controlcenter` namespace is present
/// anywhere in the saved order, the localized alias copies are redundant
/// and can be pruned. (#1080)
@Suite("Localized Control Center ghost pruning")
struct LocalizedControlCenterGhostPruningTests {
    @Test("A Control Centre alias ghost is pruned when the canonical namespace is present")
    func localizedAliasGhostIsPruned() {
        let pruned = LayoutSolver.prunedSectionOrder(
            [
                "hidden": [
                    "com.apple.controlcenter:WiFi",
                    "com.lwouis.alt-tab-macos:Item-0",
                    "Control Centre:Item-0:8",
                    "Control Centre:Item-0:10",
                ],
            ],
            displayNameAliases: ["Control Centre"]
        )

        let kept = pruned["hidden"] ?? []
        #expect(kept.contains("com.apple.controlcenter:WiFi"))
        #expect(kept.contains("com.lwouis.alt-tab-macos:Item-0"))
        #expect(!kept.contains("Control Centre:Item-0:8"))
        #expect(!kept.contains("Control Centre:Item-0:10"))
    }

    @Test("A localized alias ghost is kept when no canonical entry exists")
    func localizedAliasGhostSurvivesWithoutCanonicalTwin() {
        // No com.apple.controlcenter:* entry anywhere, and the title is
        // not a known Control Center module name, so it may be the only
        // identity a bundle-ID-less Control Center slot ever got. Deleting
        // it would lose the user's placement (#949 protection).
        let pruned = LayoutSolver.prunedSectionOrder(
            ["hidden": ["Control Centre:SomeUniqueApp"]],
            displayNameAliases: ["Control Centre"]
        )

        #expect(pruned["hidden"] == ["Control Centre:SomeUniqueApp"])
    }

    @Test("A whitespace-namespaced non-alias ghost is not pruned by the alias rule")
    func whitespaceNonAliasGhostIsNotPrunedByAliasRule() {
        // A third-party app whose display name has a space but is not a
        // Control Center alias stays protected by #949: we do not know it
        // has a canonical twin.
        let pruned = LayoutSolver.prunedSectionOrder(
            ["hidden": ["Some App:Item-0", "com.example.other:Item-0"]],
            displayNameAliases: ["Control Centre"]
        )

        #expect(pruned["hidden"]?.contains("Some App:Item-0") == true)
    }

    @Test("An instance-indexed Item-N alias ghost is pruned when the canonical namespace is present")
    func instanceIndexedItemNGhostIsPruned() {
        // The exact shape from #1080's report: Control Centre:Item-0:13, with
        // the :N instance suffix the windowID-sort enumeration assigns. The
        // alias rule prunes it alongside the canonical com.apple.controlcenter
        // entries; the suffix does not protect it.
        let pruned = LayoutSolver.prunedSectionOrder(
            [
                "hidden": [
                    "com.apple.controlcenter:WiFi",
                    "Control Centre:Item-0:13",
                    "com.lwouis.alt-tab-macos:Item-0",
                ],
            ],
            displayNameAliases: ["Control Centre"]
        )

        let kept = pruned["hidden"] ?? []
        #expect(kept.contains("com.apple.controlcenter:WiFi"))
        #expect(kept.contains("com.lwouis.alt-tab-macos:Item-0"))
        #expect(!kept.contains("Control Centre:Item-0:13"))
    }
}
