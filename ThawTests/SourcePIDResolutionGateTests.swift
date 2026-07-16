//
//  SourcePIDResolutionGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the identity-resolution gate consulted before a saved-layout
/// bulk apply.
///
/// When the MenuBarItemService XPC connection fails, most third-party items
/// resolve to a nil sourcePID and collapse to ambiguous Control-Center-owned
/// identifiers. Dispatching the bulk apply in that state rearranges items that
/// cannot be matched to the saved layout. The gate must trip on that
/// majority-unresolved signature while tolerating the small number of system
/// items (WiFi, Clock, BentoBox) that legitimately resolve to nil.
final class SourcePIDResolutionGateTests: XCTestCase {
    func testHealthyBarWithSystemItemNilsDoesNotTrip() {
        // 27 items, 3 system items unresolved — the everyday shape.
        XCTAssertFalse(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 3, itemCount: 27)
        )
    }

    func testColdStartMinorityShareDoesNotTrip() {
        // Observed during service warm-up: 9 of 27 unresolved on the first
        // cache pass, resolving fully a moment later.
        XCTAssertFalse(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 9, itemCount: 27)
        )
    }

    func testResolutionFailureSignatureTrips() {
        // Observed with a failed XPC connection: 21 of 24 unresolved.
        XCTAssertTrue(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 21, itemCount: 24)
        )
    }

    func testExactMajorityBoundary() {
        XCTAssertFalse(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 12, itemCount: 24)
        )
        XCTAssertTrue(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 13, itemCount: 24)
        )
    }

    func testTinyItemSetsNeverTrip() {
        // Below the floor, a legitimate handful of system-item nils would
        // read as a majority; the gate must stay out of the way.
        XCTAssertFalse(
            MenuBarItemManager.majorityOfSourcePIDsUnresolved(unresolvedCount: 3, itemCount: 3)
        )
    }
}
