//
//  ShouldPersistSavedOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.shouldPersistSavedOrder, the
/// pure truth-table gate consumed by uncheckedCacheItems to decide
/// whether to write savedSectionOrder for the current cache snapshot.
///
/// Pins down which in-flight orchestrator signals block a save. A
/// regression where any of these flags is dropped from the gate is
/// caught by the corresponding test below.
final class ShouldPersistSavedOrderTests: XCTestCase {
    /// All clear: every gate flag is false and no temporary contexts.
    /// The expected state for ordinary cache cycles between user
    /// actions.
    func testAllFalseAndContextsEmptyPersists() {
        XCTAssertTrue(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true
        ))
    }

    /// Restore in flight: the cross-section / within-section restore
    /// loop is currently moving items; intermediate cache states must
    /// not be persisted.
    func testRestoringItemOrderBlocks() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: true,
            isResettingLayout: false,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true
        ))
    }

    /// Layout reset in flight (the user-triggered "Reset Layout" pass);
    /// transient mid-reset state is not the user's intent.
    func testResettingLayoutBlocks() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: true,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true
        ))
    }

    /// Cold-boot settling window: many apps register their NSStatusItems
    /// in quick succession; capturing a snapshot mid-settling can
    /// persist sourcePID-unresolved placeholder identifiers.
    func testInStartupSettlingBlocks() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: true,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true
        ))
    }

    /// Profile apply in flight: applyProfileLayout owns the live layout
    /// and is moving items to match the profile spec. A nested cache
    /// cycle that clobbers isRestoringItemOrder (e.g. a failed restore
    /// returning false) must not let the partial layout reach disk.
    func testApplyingProfileLayoutBlocks() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            isApplyingProfileLayout: true,
            temporarilyShownItemContextsIsEmpty: true
        ))
    }

    /// Any temporarily-shown item is in flight: uncheckedCacheItems
    /// will route the item's cache entry to its return destination
    /// instead of its live visible position, so the save must wait
    /// until the rehide completes (or fails into pendingRelocations
    /// where the separate pendingRehideTagIdentifiers filter takes
    /// over).
    func testTemporarilyShownContextsNonEmptyBlocks() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: false
        ))
    }

    /// Two flags simultaneously: any blocking flag is sufficient to
    /// block the save. Sanity-check that the gate is the AND of all
    /// per-flag predicates rather than counting.
    func testMultipleBlockingFlagsAllBlock() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: true,
            isResettingLayout: true,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true
        ))
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: true,
            isApplyingProfileLayout: true,
            temporarilyShownItemContextsIsEmpty: true
        ))
    }
}
