//
//  EarlySavedLayoutRestrictionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the narrowing applied to the saved order by the early,
/// resolved-identities-only apply that runs during startup settling.
///
/// Without it the bar keeps macOS's arrangement until every sourcePID
/// resolves (~8 s on a dense bar). It is safe because `planLCSMoveSequence`
/// leaves identifiers dropped here untouched rather than mispositioned.
@Suite("Early saved-layout restriction")
struct EarlySavedLayoutRestrictionTests {
    // `applySavedLayout` needs a live `appState` and real window server
    // items, so only the pure narrowing helper is covered.

    @Test("Unresolved identifiers are dropped from the desired order")
    func unresolvedIdentifiersAreDropped() {
        let saved = [
            "visible": ["com.a:One", "com.b:Two"],
            "hidden": ["com.c:Three", "com.d:Four"],
        ]

        let restricted = MenuBarItemManager.savedOrderRestrictedToResolvedIdentities(
            savedSectionOrder: saved,
            resolvedIdentifiers: ["com.a:One", "com.d:Four"]
        )

        #expect(restricted["visible"] == ["com.a:One"])
        #expect(restricted["hidden"] == ["com.d:Four"])
    }

    @Test("Relative order within a section is preserved")
    func relativeOrderIsPreserved() {
        // The surviving identifiers must keep their saved sequence, or the
        // early pass would enact an order the user never chose.
        let saved = ["visible": ["com.a:One", "com.b:Two", "com.c:Three", "com.d:Four"]]

        let restricted = MenuBarItemManager.savedOrderRestrictedToResolvedIdentities(
            savedSectionOrder: saved,
            resolvedIdentifiers: ["com.d:Four", "com.a:One", "com.c:Three"]
        )

        #expect(restricted["visible"] == ["com.a:One", "com.c:Three", "com.d:Four"])
    }

    /// Matching on the base identifier would make `Item-0:2` a move target
    /// because `Item-0:1` resolved.
    @Test("A resolved sibling does not admit an unresolved instance")
    func resolvedSiblingDoesNotAdmitUnresolvedInstance() {
        let saved = [
            "visible": ["com.apple.controlcenter:Item-0:1"],
            "hidden": ["com.apple.controlcenter:Item-0:2"],
        ]

        let restricted = MenuBarItemManager.savedOrderRestrictedToResolvedIdentities(
            savedSectionOrder: saved,
            resolvedIdentifiers: ["com.apple.controlcenter:Item-0:1"]
        )

        #expect(restricted["visible"] == ["com.apple.controlcenter:Item-0:1"])
        #expect(restricted["hidden"] == [])
    }

    /// The caller distinguishes "nothing resolved yet" from "section absent",
    /// and the hidden-section room check needs a real count.
    @Test("Section keys survive even when fully emptied")
    func sectionKeysSurviveEmptying() {
        let saved = [
            "visible": ["com.a:One"],
            "hidden": ["com.b:Two"],
            "alwaysHidden": ["com.c:Three"],
        ]

        let restricted = MenuBarItemManager.savedOrderRestrictedToResolvedIdentities(
            savedSectionOrder: saved,
            resolvedIdentifiers: ["com.a:One"]
        )

        #expect(Set(restricted.keys) == ["visible", "hidden", "alwaysHidden"])
        #expect(restricted["hidden"] == [])
        #expect(restricted["alwaysHidden"] == [])
    }

    /// The caller abandons the early pass on this and waits for settling-end.
    @Test("Nothing resolved leaves every section empty")
    func nothingResolvedLeavesEverySectionEmpty() {
        let saved = [
            "visible": ["com.a:One", "com.b:Two"],
            "hidden": ["com.c:Three"],
        ]

        let restricted = MenuBarItemManager.savedOrderRestrictedToResolvedIdentities(
            savedSectionOrder: saved,
            resolvedIdentifiers: []
        )

        #expect(!restricted.values.contains { !$0.isEmpty })
    }
}
