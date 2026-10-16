//
//  LayoutResetReentrancyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The re-entrancy guard on `resetLayoutToFreshState()`.
///
/// A second concurrent reset used to overwrite the single cache continuation,
/// stranding the first `await` so its `defer` never cleared `isResettingLayout`.
/// That disabled `shouldPersistSavedOrder` for the session: nothing was ever saved.
///
/// A real reset needs the window server, so tests set `isResettingLayout`
/// directly. Serialized because each builds a live `MenuBarItemManager` that
/// reaches the shared logger, and the rejected reset's `await` could interleave.
@MainActor
@Suite("Layout reset re-entrancy", .serialized)
struct LayoutResetReentrancyTests {
    @Test("A concurrent reset is rejected with .alreadyInProgress")
    func concurrentResetThrowsAlreadyInProgress() async {
        let manager = MenuBarItemManager()
        manager.isResettingLayout = true

        do {
            _ = try await manager.resetLayoutToFreshState()
            Issue.record("resetLayoutToFreshState() must throw while a reset is already in progress")
        } catch let error as MenuBarItemManager.LayoutResetError {
            guard case .alreadyInProgress = error else {
                Issue.record("Expected .alreadyInProgress, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected LayoutResetError.alreadyInProgress, got \(error)")
        }
    }

    /// If the rejected call's `defer` ran, it would clear the flag under the
    /// in-flight reset and bring back the lost-saves bug.
    @Test("A rejected reset leaves the in-flight reset's flag set")
    func rejectedResetDoesNotClearInFlightFlag() async {
        let manager = MenuBarItemManager()
        manager.isResettingLayout = true

        _ = try? await manager.resetLayoutToFreshState()

        #expect(
            manager.isResettingLayout,
            "A rejected concurrent reset must leave the in-flight reset's flag untouched"
        )
    }

    /// A fresh manager must not start in a rejecting state.
    @Test("A fresh manager does not report a reset already in progress")
    func freshManagerDoesNotRejectFirstReset() {
        let manager = MenuBarItemManager()
        #expect(!manager.isResettingLayout, "A fresh manager must not report a reset already in progress")
    }
}
