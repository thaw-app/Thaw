//
//  CanonicalIdentifierTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Rewrites persisted identifiers after an item is renamed from its helper to
/// the installed app. Without it, every saved entry under the helper name stops
/// matching; Little Snitch is the only alias and the item whose saved position
/// users already struggle to keep.
@Suite("Canonical identifier migration")
struct CanonicalIdentifierTests {
    @Test("A helper-named entry is rewritten to the app")
    func helperEntryRewritten() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:Item-0")
                == "at.obdev.littlesnitch:Item-0"
        )
    }

    /// The instance index rides along, so two instances stay distinct.
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

    /// A bare namespace migrates without gaining a stray separator.
    @Test("A namespace with no separator migrates without gaining one")
    func bareNamespaceMigrates() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent")
                == "at.obdev.littlesnitch"
        )
    }

    /// Pruning has its own rule for empty titles, so migration must not turn one into a bare namespace.
    @Test("An empty title keeps its separator")
    func emptyTitleKeepsSeparator() {
        #expect(
            LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:")
                == "at.obdev.littlesnitch:"
        )
    }

    /// Migration runs on every load, so it must be idempotent.
    @Test("Migrating twice changes nothing further")
    func migrationIsIdempotent() {
        let once = LayoutSolver.canonicalIdentifier("at.obdev.littlesnitch.agent:Item-0")
        #expect(LayoutSolver.canonicalIdentifier(once) == once)
    }

    /// A NewItemsPlacement anchor saved under the helper name matches the live app name.
    @Test("A helper-named anchor matches its canonical live identifier")
    func newItemsAnchorMatchesCanonicalized() {
        #expect(
            LayoutSolver.newItemsAnchorMatches(
                "at.obdev.littlesnitch:Item-0",
                "at.obdev.littlesnitch.agent:Item-0"
            )
        )
        #expect(
            !LayoutSolver.newItemsAnchorMatches(
                "at.obdev.littlesnitch:Item-0",
                "com.other.app:Item-0"
            )
        )
    }

    /// Entries are rewritten in place, never rearranged (#885).
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

    /// Migration must run before pruning, or the renamed entry is discarded as unmatchable.
    @Test("Migrating before pruning preserves the renamed entry")
    func migrationSurvivesPruning() {
        let stored = ["visible": ["at.obdev.littlesnitch.agent:Item-0"]]
        let pruned = LayoutSolver.prunedSectionOrder(
            LayoutSolver.canonicalizedSectionOrder(stored)
        )

        #expect(pruned["visible"] == ["at.obdev.littlesnitch:Item-0"])
    }
}
