//
//  ShouldPersistSavedOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for LayoutSolver.shouldPersistSavedOrder, the
/// pure truth-table gate consumed by uncheckedCacheItems to decide
/// whether to write savedSectionOrder for the current cache snapshot.
///
/// Pins down which in-flight orchestrator signals block a save. A
/// regression where any of these flags is dropped from the gate is
/// caught by the corresponding test below.
@Suite("Should persist saved order")
struct ShouldPersistSavedOrderTests {
    /// All clear: every gate flag is false and no temporary contexts.
    /// The expected state for ordinary cache cycles between user
    /// actions.
    @Test("All flags clear and no temporary contexts persists")
    func allFalseAndContextsEmptyPersists() {
        #expect(LayoutSolver.shouldPersistSavedOrder(.init()))
    }

    /// Restore in flight: the cross-section / within-section restore
    /// loop is currently moving items; intermediate cache states must
    /// not be persisted.
    @Test("A restore in flight blocks the save")
    func restoringItemOrderBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isRestoringItemOrder: true
            )
        ))
    }

    /// Layout reset in flight (the user-triggered "Reset Layout" pass);
    /// transient mid-reset state is not the user's intent.
    @Test("A layout reset in flight blocks the save")
    func resettingLayoutBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isResettingLayout: true
            )
        ))
    }

    /// Cold-boot settling window: many apps register their NSStatusItems
    /// in quick succession; capturing a snapshot mid-settling can
    /// persist sourcePID-unresolved placeholder identifiers.
    @Test("The cold-boot settling window blocks the save")
    func inStartupSettlingBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isInStartupSettling: true
            )
        ))
    }

    /// Profile apply in flight: applyProfileLayout owns the live layout
    /// and is moving items to match the profile spec. A nested cache
    /// cycle that clobbers isRestoringItemOrder (e.g. a failed restore
    /// returning false) must not let the partial layout reach disk.
    @Test("A profile apply in flight blocks the save")
    func applyingProfileLayoutBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isApplyingProfileLayout: true
            )
        ))
    }

    /// Any temporarily-shown item is in flight: uncheckedCacheItems
    /// will route the item's cache entry to its return destination
    /// instead of its live visible position, so the save must wait
    /// until the rehide completes (or fails into pendingRelocations
    /// where the separate pendingRehideTagIdentifiers filter takes
    /// over).
    @Test("A temporarily-shown item in flight blocks the save")
    func temporarilyShownContextsNonEmptyBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                temporarilyShownItemContextsIsEmpty: false
            )
        ))
    }

    /// A pending layout divergence blocks the save: applySavedLayout
    /// observed a divergence on this cycle but is waiting for a second
    /// consecutive confirmation before correcting it. The current cache
    /// reflects a transient macOS rebuild (e.g. a space switch
    /// re-exposing hidden items as visible); persisting it now would
    /// bake that transient state into the saved layout (#736).
    @Test("A pending layout divergence blocks the save")
    func pendingDivergenceBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hasPendingDivergence: true
            )
        ))
    }

    /// Two flags simultaneously: any blocking flag is sufficient to
    /// block the save. Sanity-check that the gate is the AND of all
    /// per-flag predicates rather than counting.
    @Test("Any one of several blocking flags is enough to block")
    func multipleBlockingFlagsAllBlock() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isRestoringItemOrder: true,
                isResettingLayout: true
            )
        ))
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isInStartupSettling: true,
                isApplyingProfileLayout: true
            )
        ))
    }
}
