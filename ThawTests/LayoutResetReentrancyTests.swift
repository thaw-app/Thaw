//
//  LayoutResetReentrancyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the re-entrancy guard on `resetLayoutToFreshState()`.
///
/// Before this fix, `resetLayoutToFreshState` had no re-entrancy guard: a
/// second concurrent invocation would overwrite the single background-cache
/// continuation slot, permanently stranding the first invocation's `await`.
/// Because the first invocation's `defer { isResettingLayout = false }` never
/// ran, `isResettingLayout` stayed `true` for the rest of the session, which
/// silently disabled `shouldPersistSavedOrder` (see `LayoutSolver.swift`) —
/// the user could rearrange the menu bar and nothing would ever be saved.
///
/// Driving a full reset through the window server is impractical in a unit
/// test, so these tests set `isResettingLayout` directly and assert on the
/// guard's observable behavior rather than exercising the real reset body.
/// Serialized: each test builds a live `MenuBarItemManager`, whose reset path
/// reaches the process-wide diagnostic logger, and the `await` inside the
/// rejected reset would otherwise let two managers interleave on the main
/// actor.
@MainActor
@Suite("Layout reset re-entrancy", .serialized)
struct LayoutResetReentrancyTests {
    /// A reset attempted while another reset is already in flight must be
    /// rejected with `.alreadyInProgress` rather than silently overwriting
    /// the in-flight reset's state.
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

    /// A rejected concurrent reset must not clear `isResettingLayout`. If the
    /// rejected call's own `defer` ran, it would clear the flag out from under
    /// the still-in-flight first reset, reproducing the original
    /// silent-non-persistence bug.
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

    /// When no reset is in flight, the guard must not fire — the flag itself
    /// (rather than the guard misfiring) is what's under test elsewhere, but
    /// this pins that a fresh manager does not start in a rejecting state.
    @Test("A fresh manager does not report a reset already in progress")
    func freshManagerDoesNotRejectFirstReset() {
        let manager = MenuBarItemManager()
        #expect(!manager.isResettingLayout, "A fresh manager must not report a reset already in progress")
    }
}
