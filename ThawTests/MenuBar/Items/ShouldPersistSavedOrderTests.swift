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

    /// The always-hidden divider went unresolved for this cache cycle:
    /// without that boundary every always-hidden item degrades to
    /// `.hidden`, and persisting the misread would make it the user's
    /// layout (#849).
    @Test("An unresolved always-hidden section blocks the save")
    func alwaysHiddenSectionUnresolvedBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                alwaysHiddenSectionResolved: false
            )
        ))
    }

    /// The hidden section's span between the dividers has closed to
    /// zero while the saved layout still expects hidden items: the cache
    /// resolves those items as visible, and persisting would move them
    /// out of the hidden section for good (#795).
    @Test("A hidden section without room blocks the save")
    func hiddenSectionWithoutRoomBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hiddenSectionHasRoom: false
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

    /// An unfinished move batch blocks the save: the bulk apply planned
    /// moves it never enacted, so what the bar shows is where the batch
    /// stopped rather than a layout anyone chose. Persisting it replaces
    /// the order the batch was restoring, and the next pass then measures
    /// against the partial result — the drift #900 describes.
    @Test("An unfinished move batch blocks the save")
    func unfinishedMoveBatchBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hasUnfinishedMoveBatch: true
            )
        ))
    }

    /// The move cooldown blocks the save, because `applySavedLayout` honours
    /// the same window: for five seconds after a move it declines to restore.
    /// A save allowed inside that window writes the bar as it stands while
    /// the only thing that would have corrected it is standing down, so the
    /// interrupted arrangement becomes the saved one (#958).
    @Test("The move cooldown blocks the save")
    func moveCooldownBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isWithinMoveCooldown: true
            )
        ))
    }

    /// The menu bar changing display blocks the save. The multi-display gate
    /// can only see items still classified as visible, so a relocation that
    /// strands items in the wrong section removes its own evidence: in the
    /// #958 log it fired correctly with sixteen visible items and then passed
    /// two and a half minutes later when only four were left.
    @Test("The menu bar changing display blocks the save")
    func displayChangeBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                menuBarDisplayChanged: true
            )
        ))
    }
}
