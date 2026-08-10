//
//  CanonicalIdentifierTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the migration that rewrites persisted identifiers after an
/// item is renamed from its helper to the app the user installed.
///
/// Renaming changes `uniqueIdentifier`, so every entry already on disk
/// under the helper's name stops matching. Little Snitch is both the only
/// current alias and the item whose saved position users already struggle
/// to keep (#372, #575, #643, #651, #709) — orphaning it would land the
/// regression on the least forgiving case in the tracker.
@Suite("Canonical identifier migration")
struct CanonicalIdentifierTests {
    /// The migration this exists for.
    @Test("A helper-named entry is rewritten to the app")
    func helperEntryRewritten() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:Item-0")
                == "at.obdev.littlesnitch:Item-0"
        )
    }

    /// An instance index is part of the title portion and rides along
    /// untouched, so two instances stay distinct after migration.
    @Test("An instance index survives the rewrite")
    func instanceIndexSurvives() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:Item-0:1")
                == "at.obdev.littlesnitch:Item-0:1"
        )
    }

    /// Everything not aliased is returned byte-for-byte.
    @Test(
        "Unaliased identifiers pass through unchanged",
        arguments: [
            "com.apple.controlcenter:Item-0",
            "com.microsoft.OneDrive-mac:OneDrive",
            "at.obdev.littlesnitch:Item-0",
            "eu.exelban.Stats:CPU",
            "",
        ]
    )
    func unaliasedPassThrough(identifier: String) {
        #expect(LayoutSolver.canonicalIdentifier(identifier) == identifier)
    }

    /// A bare namespace with no title still migrates rather than growing a
    /// stray separator.
    @Test("A namespace with no separator migrates without gaining one")
    func bareNamespaceMigrates() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent")
                == "at.obdev.littlesnitch"
        )
    }

    /// An empty title is preserved as an empty title: pruning has its own
    /// rule for those, and migration must not disguise one as a bare
    /// namespace.
    @Test("An empty title keeps its separator")
    func emptyTitleKeepsSeparator() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:")
                == "at.obdev.littlesnitch:"
        )
    }

    /// Migration is idempotent — it runs on every load.
    @Test("Migrating twice changes nothing further")
    func migrationIsIdempotent() {
        let once = LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:Item-0")
        #expect(LayoutSolver.canonicalIdentifier(once) == once)
    }

    /// Across a whole saved order: sections keep their keys, and order
    /// within a section is preserved — entries are rewritten in place,
    /// never rearranged (#885).
    @Test("A saved order is migrated in place")
    func savedOrderMigratedInPlace() {
        let migrated = LayoutSolver.canonicalizedSectionOrder([
            "visible": ["eu.exelban.Stats:CPU", "at.obdev.littlesnitch.agent:Item-0"],
            "hidden": ["com.apple.controlcenter:WiFi"],
            "alwaysHidden": [],
        ])

        #expect(migrated["visible"] == ["eu.exelban.Stats:CPU", "at.obdev.littlesnitch:Item-0"])
        #expect(migrated["hidden"] == ["com.apple.controlcenter:WiFi"])
        #expect(migrated["alwaysHidden"] == [])
        #expect(migrated.keys.sorted() == ["alwaysHidden", "hidden", "visible"])
    }

    /// The migration has to run *before* pruning, or the renamed entry is
    /// discarded as unmatchable before it can be rescued. This pins the
    /// composition the loader relies on.
    @Test("Migrating before pruning preserves the renamed entry")
    func migrationSurvivesPruning() {
        let stored = ["visible": ["at.obdev.littlesnitch.agent:Item-0"]]
        let pruned = LayoutSolver.prunedSectionOrder(
            LayoutSolver.canonicalizedSectionOrder(stored)
        )

        #expect(pruned["visible"] == ["at.obdev.littlesnitch:Item-0"])
    }
}
