//
//  ShouldPersistSavedOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// `LayoutSolver.shouldPersistSavedOrder`, the gate uncheckedCacheItems uses
/// before writing savedSectionOrder. Each in-flight signal that blocks a save
/// has its own test.
@Suite("Should persist saved order")
struct ShouldPersistSavedOrderTests {
    /// The ordinary state between user actions.
    @Test("All flags clear and no temporary contexts persists")
    func allFalseAndContextsEmptyPersists() {
        #expect(LayoutSolver.shouldPersistSavedOrder(.init()))
    }

    /// The restore loop is moving items; intermediate states must not persist.
    @Test("A restore in flight blocks the save")
    func restoringItemOrderBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isRestoringItemOrder: true
            )
        ))
    }

    /// Mid-reset state is not the user's intent.
    @Test("A layout reset in flight blocks the save")
    func resettingLayoutBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isResettingLayout: true
            )
        ))
    }

    /// Apps register status items in quick succession at boot, and a snapshot
    /// then can persist sourcePID-unresolved placeholder identifiers.
    @Test("The cold-boot settling window blocks the save")
    func inStartupSettlingBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isInStartupSettling: true
            )
        ))
    }

    /// applyProfileLayout owns the layout; a nested cycle that clears
    /// isRestoringItemOrder (a failed restore) must not let the partial layout reach disk.
    @Test("A profile apply in flight blocks the save")
    func applyingProfileLayoutBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isApplyingProfileLayout: true
            )
        ))
    }

    /// uncheckedCacheItems routes a temporarily shown item to its return destination,
    /// so the save waits for the rehide (or for pendingRehideTagIdentifiers to take over).
    @Test("A temporarily-shown item in flight blocks the save")
    func temporarilyShownContextsNonEmptyBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                temporarilyShownItemContextsIsEmpty: false
            )
        ))
    }

    /// applySavedLayout is waiting for a second confirmation of a divergence; the
    /// cache may reflect a transient macOS rebuild such as a space switch (#736).
    @Test("A pending layout divergence blocks the save")
    func pendingDivergenceBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hasPendingDivergence: true
            )
        ))
    }

    /// Without that divider every always-hidden item degrades to `.hidden` (#849).
    @Test("An unresolved always-hidden section blocks the save")
    func alwaysHiddenSectionUnresolvedBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                alwaysHiddenSectionResolved: false
            )
        ))
    }

    /// A closed span resolves expected hidden items as visible, and saving would
    /// move them out of hidden for good (#795).
    @Test("A hidden section without room blocks the save")
    func hiddenSectionWithoutRoomBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hiddenSectionHasRoom: false
            )
        ))
    }

    /// Any one blocking flag is enough; the gate does not count them.
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

    /// A partial batch leaves the bar where it stopped; saving that replaces the
    /// order being restored and the next pass drifts further (#900).
    @Test("An unfinished move batch blocks the save")
    func unfinishedMoveBatchBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                hasUnfinishedMoveBatch: true
            )
        ))
    }

    /// `applySavedLayout` declines to restore for five seconds after a move, so a
    /// save in that window would make the interrupted arrangement stick (#958).
    @Test("The move cooldown blocks the save")
    func moveCooldownBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                isWithinMoveCooldown: true
            )
        ))
    }

    /// The multi-display gate only sees items still classified visible, so a
    /// relocation removes its own evidence: it fired with sixteen visible items,
    /// then passed minutes later with four (#958).
    @Test("The menu bar changing display blocks the save")
    func displayChangeBlocks() {
        #expect(!LayoutSolver.shouldPersistSavedOrder(
            .init(
                menuBarDisplayChanged: true
            )
        ))
    }
}
