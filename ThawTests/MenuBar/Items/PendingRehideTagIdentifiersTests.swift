//
//  PendingRehideTagIdentifiersTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

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
@Suite("Pending rehide tag identifiers")
struct PendingRehideTagIdentifiersTests {
    private let waitForRelaunchPrefix = "waitForRelaunch:"

    /// Empty inputs produce an empty set.
    @Test("Empty inputs produce an empty set")
    func emptyInputsReturnsEmpty() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [:],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == [])
    }

    /// Active return destination only: in-flight context has been
    /// dropped but the return-destination metadata survives until the
    /// app relaunches. The tag is in the result set.
    @Test("An active return destination contributes its tag")
    func activeReturnDestinationIncludesTag() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [
                "com.example.app:Status": ["neighbor": "com.other.app:Status", "position": "left"],
            ],
            pendingRelocations: [:],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == ["com.example.app:Status"])
    }

    /// waitForRelaunch sentinel only: the rehide hit the per-session
    /// retry cap and was suspended. pendingRelocations carries the
    /// sentinel-prefixed value; the tag is in the result set.
    @Test("A waitForRelaunch sentinel contributes its tag")
    func waitForRelaunchSentinelIncludesTag() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [
                "com.example.app:Status": "waitForRelaunch:12345:hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == ["com.example.app:Status"])
    }

    /// Non-sentinel pendingRelocations value: this is the ordinary
    /// "remember the original section" entry written before a
    /// temporarilyShow move (the value is a section key like "hidden"
    /// or "alwaysHidden", not the sentinel). It must NOT be treated
    /// as a rehide signal — the in-flight context handles the
    /// suppression while the rehide is still attempted.
    @Test("A non-sentinel pending relocation is excluded")
    func nonSentinelPendingRelocationExcluded() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [
                "com.example.app:Status": "hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == [])
    }

    /// Both sources contribute disjoint tags: the union is the result.
    @Test("Disjoint sources produce the union of their tags")
    func disjointSourcesProduceUnion() {
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
        #expect(result == ["com.a.app:Status", "com.b.app:Status"])
    }

    /// Same tag appears in both sources: the set deduplicates.
    @Test("A tag present in both sources is reported once")
    func overlappingSourcesDeduplicate() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [
                "com.example.app:Status": ["neighbor": "com.other.app:Status", "position": "left"],
            ],
            pendingRelocations: [
                "com.example.app:Status": "waitForRelaunch:42:hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == ["com.example.app:Status"])
    }

    /// Prefix matching is strict: a value whose content happens to
    /// contain the prefix substring later in the string is not a
    /// sentinel. Only true `hasPrefix` matches count.
    @Test("Sentinel matching is anchored to the start of the value")
    func prefixMatchIsAnchored() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [
                "com.example.app:Status": "preludeWordwaitForRelaunch:12345:hidden",
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == [])
    }
}
