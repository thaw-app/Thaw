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
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
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
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
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
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
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
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
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
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
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
            temporarilyShownItemContextsIsEmpty: false,
            alwaysHiddenSectionResolved: true
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
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
        ))
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: true,
            isApplyingProfileLayout: true,
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
        ))
    }

    // MARK: - Always-hidden divider (#849)

    /// The regression itself: the always-hidden divider went unresolved
    /// for a single cache cycle, findSection collapsed the always-hidden
    /// section into hidden, and the save wrote that reading down as the
    /// user's layout. Every other flag is clear here, which is what let
    /// the old gate through.
    func testUnresolvedAlwaysHiddenSectionBlocks() {
        XCTAssertFalse(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: false
        ))
    }

    /// A resolved divider is the ordinary case and must not be blocked.
    func testResolvedAlwaysHiddenSectionPersists() {
        XCTAssertTrue(LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            isApplyingProfileLayout: false,
            temporarilyShownItemContextsIsEmpty: true,
            alwaysHiddenSectionResolved: true
        ))
    }
}

// MARK: - IsAlwaysHiddenSectionResolvedTests

/// Covers the predicate feeding the gate's always-hidden input. The
/// distinction it draws is what keeps the #849 fix from becoming a bug of
/// its own: a missing divider is only evidence of a problem when the
/// section that owns it is turned on.
final class IsAlwaysHiddenSectionResolvedTests: XCTestCase {
    /// Divider present, section on: the normal healthy state.
    func testPresentDividerIsResolved() {
        XCTAssertTrue(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: true,
            isAlwaysHiddenSectionEnabled: true
        ))
    }

    /// The #849 state: the section is on, so its items are real, but the
    /// boundary that identifies them is missing this cycle.
    func testMissingDividerWithEnabledSectionIsUnresolved() {
        XCTAssertFalse(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: false,
            isAlwaysHiddenSectionEnabled: true
        ))
    }

    /// Users who never enabled the always-hidden section have no divider
    /// by design. Treating that as unresolved would block their layout
    /// from ever being saved — trading #849 for a worse bug.
    func testMissingDividerWithDisabledSectionIsResolved() {
        XCTAssertTrue(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: false,
            isAlwaysHiddenSectionEnabled: false
        ))
    }

    /// A divider that exists while the section is off is still not a
    /// reason to block.
    func testPresentDividerWithDisabledSectionIsResolved() {
        XCTAssertTrue(LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: true,
            isAlwaysHiddenSectionEnabled: false
        ))
    }
}
