//
//  PendingRehideTagIdentifiersTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.pendingRehideTagIdentifiers,
/// the helper saveSectionOrder uses to identify items whose true
/// section is elsewhere despite their current cache position.
///
/// Pins down the post-rehide-give-up bug: a temporarily-shown item
/// whose app quit before rehide leaves pendingRelocations marked with
/// a waitForRelaunch sentinel; pendingReturnDestinations may also be
/// populated. Both signals must be treated as "this item belongs
/// elsewhere" so planSectionOrder preserves the item's original
/// saved-section slot instead of capturing its live visible position.
final class PendingRehideTagIdentifiersTests: XCTestCase {
    private let waitForRelaunchPrefix = "waitForRelaunch:"

    /// Empty inputs produce an empty set.
    func testEmptyInputsReturnsEmpty() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [:],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, [])
    }

    /// Active return destination only: in-flight context has been
    /// dropped but the return-destination metadata survives until the
    /// app relaunches. The tag is in the result set.
    func testActiveReturnDestinationIncludesTag() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [
                "com.example.app:Status": ["neighbor": "com.other.app:Status", "position": "left"],
            ],
            pendingRelocations: [:],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, ["com.example.app:Status"])
    }

    /// waitForRelaunch sentinel only: the rehide hit the per-session
    /// retry cap and was suspended. pendingRelocations carries the
    /// sentinel-prefixed value; the tag is in the result set.
    func testWaitForRelaunchSentinelIncludesTag() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [
                "com.example.app:Status": "waitForRelaunch:12345:hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, ["com.example.app:Status"])
    }

    /// Non-sentinel pendingRelocations value: this is the ordinary
    /// "remember the original section" entry written before a
    /// temporarilyShow move (the value is a section key like "hidden"
    /// or "alwaysHidden", not the sentinel). It must NOT be treated
    /// as a rehide signal — the in-flight context handles the
    /// suppression while the rehide is still attempted.
    func testNonSentinelPendingRelocationExcluded() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [
                "com.example.app:Status": "hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, [])
    }

    /// Both sources contribute disjoint tags: the union is the result.
    func testDisjointSourcesProduceUnion() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [
                "com.a.app:Status": ["neighbor": "com.x.app:Status", "position": "left"],
            ],
            pendingRelocations: [
                "com.b.app:Status": "waitForRelaunch:999:alwaysHidden",
                "com.c.app:Status": "hidden", // excluded — not a sentinel
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, ["com.a.app:Status", "com.b.app:Status"])
    }

    /// Same tag appears in both sources: the set deduplicates.
    func testOverlappingSourcesDeduplicate() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [
                "com.example.app:Status": ["neighbor": "com.other.app:Status", "position": "left"],
            ],
            pendingRelocations: [
                "com.example.app:Status": "waitForRelaunch:42:hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, ["com.example.app:Status"])
    }

    /// Prefix matching is strict: a value whose content happens to
    /// contain the prefix substring later in the string is not a
    /// sentinel. Only true `hasPrefix` matches count.
    func testPrefixMatchIsAnchored() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [
                "com.example.app:Status": "preludeWordwaitForRelaunch:12345:hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        XCTAssertEqual(result, [])
    }
}
