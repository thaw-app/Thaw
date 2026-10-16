//
//  SourcePIDResolutionGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The identity-resolution gate checked before a saved-layout bulk apply.
///
/// When the MenuBarItemService XPC connection fails, most third-party items get
/// a nil sourcePID and ambiguous Control Center identifiers, and a bulk apply
/// rearranges items it cannot match. The gate trips on a majority unresolved
/// while tolerating the few system items (WiFi, Clock, BentoBox) that are always nil.
@Suite("Source PID resolution gate")
struct SourcePIDResolutionGateTests {
    // The call sites need a live `appState` and WindowServer items, so only the
    // pure predicate is tested here.

    @Test("A healthy bar with system-item nils does not trip the gate")
    func healthyBarWithSystemItemNilsDoesNotTrip() {
        // 27 items, 3 system items unresolved: the everyday shape.
        #expect(
            !MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 3, itemCount: 27)
        )
    }

    @Test("A cold-start minority share does not trip the gate")
    func coldStartMinorityShareDoesNotTrip() {
        // Service warm-up: 9 of 27 unresolved on the first pass, resolved a moment later.
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
        // Below the floor, a few legitimate system-item nils would read as a majority.
        #expect(
            !MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 3, itemCount: 3)
        )
    }
}
