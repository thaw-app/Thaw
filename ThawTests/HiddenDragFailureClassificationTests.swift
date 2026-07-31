//
//  HiddenDragFailureClassificationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes `MenuBarItemManager.classifyHiddenDragFailure`, the pure
/// decision function that decides how the Layout settings drag handler
/// should respond to a move that threw after the drag handler's
/// resample-and-verify pass (issue #744).
///
/// Precedence: reaching the intended position beats being blocked at the
/// x=-1 sentinel; being blocked beats a missing hidden-section control item.
@Suite("Hidden drag failure classification")
struct HiddenDragFailureClassificationTests {
    /// The item actually reached its intended position (verification raced
    /// macOS's own settle): suppress, regardless of any other signal.
    @Test("Reaching the intended position suppresses the failure")
    func reachedPositionSuppresses() {
        #expect(
            MenuBarItemManager.classifyHiddenDragFailure(
                reachedPosition: true,
                isBlocked: false,
                controlItemsMissing: false
            ) == .suppress
        )
    }

    /// Reaching the position wins even when the item also reads as blocked
    /// and control items are missing -- those signals shouldn't matter once
    /// verification already confirmed success.
    @Test("Reaching the position beats blocked and missing control items")
    func reachedPositionBeatsBlockedAndControlItemsMissing() {
        #expect(
            MenuBarItemManager.classifyHiddenDragFailure(
                reachedPosition: true,
                isBlocked: true,
                controlItemsMissing: true
            ) == .suppress
        )
    }

    /// The item is stuck at the x=-1 sentinel and did not reach its
    /// position: rescue-and-retry.
    @Test("A blocked item is rescued and retried")
    func blockedRescuesAndRetries() {
        #expect(
            MenuBarItemManager.classifyHiddenDragFailure(
                reachedPosition: false,
                isBlocked: true,
                controlItemsMissing: false
            ) == .rescueAndRetry
        )
    }

    /// Being blocked wins over control items being missing: precedence
    /// matters because a blocked item is independently recoverable.
    @Test("Being blocked beats missing control items")
    func blockedBeatsControlItemsMissing() {
        #expect(
            MenuBarItemManager.classifyHiddenDragFailure(
                reachedPosition: false,
                isBlocked: true,
                controlItemsMissing: true
            ) == .rescueAndRetry
        )
    }

    /// Not blocked, but the hidden-section control item can't currently be
    /// resolved: show the calm "recovering in background" message rather
    /// than the raw error.
    @Test("Missing control items alert with the calm message")
    func controlItemsMissingAlertsWithCalmMessage() {
        #expect(
            MenuBarItemManager.classifyHiddenDragFailure(
                reachedPosition: false,
                isBlocked: false,
                controlItemsMissing: true
            ) == .alertControlItemsMissing
        )
    }

    /// None of the recoverable signals apply: fall back to the raw error
    /// alert, unchanged from before this fix.
    @Test("No recoverable signals falls back to the generic alert")
    func noSignalsAlertsGeneric() {
        #expect(
            MenuBarItemManager.classifyHiddenDragFailure(
                reachedPosition: false,
                isBlocked: false,
                controlItemsMissing: false
            ) == .alertGeneric
        )
    }
}
