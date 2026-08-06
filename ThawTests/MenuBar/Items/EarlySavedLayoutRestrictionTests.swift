//
//  EarlySavedLayoutRestrictionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the narrowing applied to the saved order by the early,
/// resolved-identities-only apply that runs during startup settling.
///
/// Without that early pass the bar sits in macOS's arrangement until every
/// sourcePID resolves, which is ~8 s on a dense bar (#881). Running early is
/// only safe because the desired order is narrowed to identifiers we can
/// currently identify: `planLCSMoveSequence` intersects current with desired,
/// so an identifier dropped here is left untouched rather than mispositioned.
@Suite("Early saved-layout restriction")
struct EarlySavedLayoutRestrictionTests {
    // NOTE: `applySavedLayout` is an instance method requiring a live
    // `appState`, real `ControlItemPair`s and Window Server items, so this
    // suite characterizes the pure narrowing helper only — matching the
    // approach in SourcePIDResolutionGateTests.

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

    /// An unresolved sibling sharing a base identifier is exactly the case
    /// the exact-match rule exists to exclude — matching on the base would
    /// make `Item-0:2` a move target on the strength of `Item-0:1` resolving.
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

    /// Section keys survive emptying so the caller can distinguish "this
    /// section has nothing resolved yet" from "this section is absent", and
    /// so the hidden-section room check reads a real count.
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

    /// The all-unresolved case is what the caller's own guard keys off to
    /// abandon the early pass entirely and wait for settling-end.
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
