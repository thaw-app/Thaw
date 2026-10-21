//
//  SavedLayoutHandoffRefreshTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/savedLayoutHandoffNeedsCacheRefresh(deferredRefreshesBeforeApply:deferredRefreshesAfterApply:)``.
///
/// A cache pass that dispatches a saved-layout apply returns without publishing
/// and leaves the refresh to the apply. An automatic apply that waited out its
/// idle gate and deferred while input stayed active scheduled none, and the
/// pass had already committed the window IDs, so the Thaw Bar showed a moved
/// item in its old section until the window IDs next changed, five minutes
/// later in the log behind this test.
@Suite("Saved-layout handoff refresh")
struct SavedLayoutHandoffRefreshTests {
    @Test("An apply that returned without scheduling a refresh needs one")
    func deferredApplyNeedsRefresh() {
        #expect(MenuBarItemManager.savedLayoutHandoffNeedsCacheRefresh(
            deferredRefreshesBeforeApply: 4,
            deferredRefreshesAfterApply: 4
        ))
    }

    @Test("An apply that scheduled its own refresh needs no second one")
    func applyWithRefreshNeedsNoSecond() {
        #expect(!MenuBarItemManager.savedLayoutHandoffNeedsCacheRefresh(
            deferredRefreshesBeforeApply: 4,
            deferredRefreshesAfterApply: 5
        ))
        #expect(!MenuBarItemManager.savedLayoutHandoffNeedsCacheRefresh(
            deferredRefreshesBeforeApply: 4,
            deferredRefreshesAfterApply: 7
        ))
    }

    /// A pass dropped at a busy cacheGate, during a drag, or discarded as mid
    /// expand/collapse doesn't complete a cycle and has to be retried, within
    /// a bound so a persistent cause can't loop forever.
    @Test("A scheduled refresh retries an incomplete pass within its bound")
    func scheduledRefreshRetriesWithinBound() {
        #expect(MenuBarItemManager.shouldRetryScheduledCacheRefresh(attemptCompleted: false, attempt: 1, maxAttempts: 10))
        #expect(MenuBarItemManager.shouldRetryScheduledCacheRefresh(attemptCompleted: false, attempt: 9, maxAttempts: 10))
        #expect(!MenuBarItemManager.shouldRetryScheduledCacheRefresh(attemptCompleted: false, attempt: 10, maxAttempts: 10))
    }

    @Test("A completed pass ends a scheduled refresh")
    func completedPassEndsRefresh() {
        #expect(!MenuBarItemManager.shouldRetryScheduledCacheRefresh(attemptCompleted: true, attempt: 1, maxAttempts: 10))
    }

    /// A discard that arrives while a retry is running is merged into it.
    /// Losing a later pass's need for persistence would skip saving the order.
    @Test("Merged retry flags stay suppressed only if every request suppressed them")
    func mergedRetryFlagsKeepEveryRequirement() {
        let suppressBoth = MenuBarItemManager.MidTransitionRetryFlags(
            suppressAutomaticMoves: true,
            suppressSavedOrderPersistence: true
        )
        let needsPersistence = MenuBarItemManager.MidTransitionRetryFlags(
            suppressAutomaticMoves: true,
            suppressSavedOrderPersistence: false
        )
        let needsMoves = MenuBarItemManager.MidTransitionRetryFlags(
            suppressAutomaticMoves: false,
            suppressSavedOrderPersistence: true
        )

        #expect(suppressBoth.merged(with: suppressBoth) == suppressBoth)
        #expect(suppressBoth.merged(with: needsPersistence) == needsPersistence)
        #expect(needsPersistence.merged(with: suppressBoth) == needsPersistence)
        #expect(needsPersistence.merged(with: needsMoves) == MenuBarItemManager.MidTransitionRetryFlags(
            suppressAutomaticMoves: false,
            suppressSavedOrderPersistence: false
        ))
    }
}
