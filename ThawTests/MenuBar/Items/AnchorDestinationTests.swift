//
//  AnchorDestinationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for LayoutSolver.anchorDestination, the
/// shared helper used by cross-section restore, within-section reorder,
/// and profile-route unmanaged placement.
///
/// Pins down: forward-first preference, backward fallback, section-
/// boundary fallback, and edge cases around index bounds.
@Suite("Anchor destination")
struct AnchorDestinationTests {
    /// A successor in the same section is preferred over a predecessor.
    /// saved=[A,B,C], moving B at idx 1, current section has A and C.
    /// Forward scan finds C → .leftOfUID(C).
    @Test("A successor in the same section is preferred over a predecessor")
    func forwardAnchorPreferredOverBackward() {
        let result = LayoutSolver.anchorDestination(
            forSavedIndex: 1,
            inSection: .visible,
            savedSequence: ["A", "B", "C"],
            currentUIDsInSection: ["A", "C"]
        )
        #expect(result == .leftOfUID("C"))
    }

    /// When no successor is in the section, backward scan picks the
    /// nearest predecessor.
    /// saved=[A,B,C], moving B at idx 1, current section has A only.
    /// Forward scan misses C; backward scan finds A → .rightOfUID(A).
    @Test("Without a successor the nearest predecessor anchors the move")
    func backwardAnchorWhenNoForwardAnchor() {
        let result = LayoutSolver.anchorDestination(
            forSavedIndex: 1,
            inSection: .visible,
            savedSequence: ["A", "B", "C"],
            currentUIDsInSection: ["A"]
        )
        #expect(result == .rightOfUID("A"))
    }

    /// When neither scan finds an anchor, fall back to section boundary.
    /// saved=[A,B,C], moving B at idx 1, current section is empty of
    /// these uids → .sectionBoundary.
    @Test("With no anchor either way the section boundary is used")
    func sectionBoundaryFallback() {
        let result = LayoutSolver.anchorDestination(
            forSavedIndex: 1,
            inSection: .hidden,
            savedSequence: ["A", "B", "C"],
            currentUIDsInSection: []
        )
        #expect(result == .sectionBoundary(.hidden))
    }

    /// Saved index 0 with a successor in current → .leftOfUID(successor).
    /// No backward scan (index 0 has nothing before it).
    @Test("A saved index of zero uses the forward successor")
    func savedIndexZeroUsesForwardSuccessor() {
        let result = LayoutSolver.anchorDestination(
            forSavedIndex: 0,
            inSection: .visible,
            savedSequence: ["A", "B", "C"],
            currentUIDsInSection: ["B"]
        )
        #expect(result == .leftOfUID("B"))
    }

    /// Saved index at end of sequence: no forward scan possible; use
    /// the nearest predecessor present in section.
    /// saved=[A,B,C], moving at idx 2 (last), current has A.
    @Test("A saved index at the end of the sequence uses the backward scan")
    func savedIndexAtEndUsesBackwardScan() {
        let result = LayoutSolver.anchorDestination(
            forSavedIndex: 2,
            inSection: .visible,
            savedSequence: ["A", "B", "C"],
            currentUIDsInSection: ["A"]
        )
        #expect(result == .rightOfUID("A"))
    }

    /// Empty saved sequence falls back to section boundary regardless
    /// of currentUIDsInSection.
    @Test("An empty saved sequence falls back to the section boundary")
    func emptySavedSequenceFallsBack() {
        let result = LayoutSolver.anchorDestination(
            forSavedIndex: 0,
            inSection: .alwaysHidden,
            savedSequence: [],
            currentUIDsInSection: ["X", "Y"]
        )
        #expect(result == .sectionBoundary(.alwaysHidden))
    }
}
