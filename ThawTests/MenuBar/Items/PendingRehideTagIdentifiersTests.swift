//
//  PendingRehideTagIdentifiersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// `LayoutSolver.pendingRehideTagIdentifiers`, which saveSectionOrder uses to
/// find items whose true section is not their current position.
///
/// When a temporarily shown item's app quits before rehide, pendingRelocations
/// holds a waitForRelaunch sentinel and pendingReturnDestinations may be set.
/// Both mean "belongs elsewhere", so planSectionOrder keeps the saved slot
/// instead of the live visible position.
@Suite("Pending rehide tag identifiers")
struct PendingRehideTagIdentifiersTests {
    private let waitForRelaunchPrefix = "waitForRelaunch:"

    @Test("Empty inputs produce an empty set")
    func emptyInputsReturnsEmpty() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [:],
            pendingRelocations: [:],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == [])
    }

    /// The in-flight context is gone but the return destination survives until relaunch.
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

    /// The rehide hit the per-session retry cap and was suspended with a sentinel.
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

    /// An ordinary "remember the original section" entry (a section key, not the
    /// sentinel) is not a rehide signal; the in-flight context handles that case.
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

    @Test("Disjoint sources produce the union of their tags")
    func disjointSourcesProduceUnion() {
        let result = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: [
                "com.a.app:Status": ["neighbor": "com.x.app:Status", "position": "left"],
            ],
            pendingRelocations: [
                "com.b.app:Status": "waitForRelaunch:999:alwaysHidden",
                "com.c.app:Status": "hidden", // excluded, not a sentinel
            ],
            waitForRelaunchPrefix: waitForRelaunchPrefix
        )
        #expect(result == ["com.a.app:Status", "com.b.app:Status"])
    }

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

    /// Only a true `hasPrefix` match is a sentinel, not the prefix later in the value.
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
