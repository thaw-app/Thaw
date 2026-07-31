//
//  SourcePIDResolutionGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the identity-resolution gate consulted before a saved-layout
/// bulk apply.
///
/// When the MenuBarItemService XPC connection fails, most third-party items
/// resolve to a nil sourcePID and collapse to ambiguous Control-Center-owned
/// identifiers. Dispatching the bulk apply in that state rearranges items that
/// cannot be matched to the saved layout. The gate must trip on that
/// majority-unresolved signature while tolerating the small number of system
/// items (WiFi, Clock, BentoBox) that legitimately resolve to nil.
@Suite("Source PID resolution gate")
struct SourcePIDResolutionGateTests {
    // NOTE: `applySavedLayout` and `applyProfileLayout` (the call sites that
    // consult this gate) are instance methods on `MenuBarItemManager` that
    // require a live `appState`, real `ControlItemPair`s, and Window Server
    // items to run — they cannot be exercised with plain fixture values the
    // way `savedLayoutSectionLookup` can (see SavedLayoutSectionLookupTests).
    // This suite is limited to characterizing the pure predicate; the
    // call-site wiring is verified structurally (grep for the call site
    // inside applySavedLayout/applyProfileLayout) rather than by unit test.

    @Test("A healthy bar with system-item nils does not trip the gate")
    func healthyBarWithSystemItemNilsDoesNotTrip() {
        // 27 items, 3 system items unresolved — the everyday shape.
        #expect(
            !MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 3, itemCount: 27)
        )
    }

    @Test("A cold-start minority share does not trip the gate")
    func coldStartMinorityShareDoesNotTrip() {
        // Observed during service warm-up: 9 of 27 unresolved on the first
        // cache pass, resolving fully a moment later.
        #expect(
            !MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 9, itemCount: 27)
        )
    }

    @Test("The resolution-failure signature trips the gate")
    func resolutionFailureSignatureTrips() {
        // Observed with a failed XPC connection: 21 of 24 unresolved.
        #expect(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 21, itemCount: 24)
        )
    }

    @Test("The exact majority boundary is respected")
    func exactMajorityBoundary() {
        #expect(
            !MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 12, itemCount: 24)
        )
        #expect(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 13, itemCount: 24)
        )
    }

    @Test("Tiny item sets never trip the gate")
    func tinyItemSetsNeverTrip() {
        // Below the floor, a legitimate handful of system-item nils would
        // read as a majority; the gate must stay out of the way.
        #expect(
            !MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 3, itemCount: 3)
        )
    }
}
