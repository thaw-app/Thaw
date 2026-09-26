//
//  HiddenDragFailureClassificationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `MenuBarItemManager.classifyHiddenDragFailure`: how the Layout
/// settings drag handler responds to a move that threw after
/// resample-and-verify (#744).
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

    /// Once verification confirmed success, blocked and missing-control-item
    /// signals do not matter.
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

    /// A blocked item is independently recoverable.
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

    /// With no recoverable signal, fall back to the raw error alert.
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
