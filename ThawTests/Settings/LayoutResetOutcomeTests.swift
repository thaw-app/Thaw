//
//  LayoutResetOutcomeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Zero failures means success only if reset ran; engineNotRunning must map to notRun, not a false success.
/// Tests cover result mapping, not live synthetic drags.
@MainActor
@Suite("Layout reset outcome")
struct LayoutResetOutcomeTests {
    typealias Status = LayoutResetFlow.ResetStatus
    typealias Target = LayoutResetFlow.ResetTarget

    static nonisolated let targets: [Target] = [.visible, .hidden, .alwaysHidden]

    // MARK: A reset that never ran

    @Test("An engine that never came up reports nothing was moved", arguments: targets)
    func engineNotRunningIsNotASweep(target: Target) {
        let status = Status.thrown(MenuBarItemManager.LayoutResetError.engineNotRunning)

        #expect(status == .notRun)
        #expect(status != .success(target), "No target may read as reset when the engine never came up")
        #expect(status != .partialFailure(0), "Nothing was attempted, so nothing failed to move")
    }

    @Test("Nothing-was-moved is shown as an error, not as a success")
    func notRunIsAnError() {
        #expect(Status.notRun.isError)
        #expect(!Status.success(.hidden).isError, "The clean sweep is the only non-error outcome")
    }

    @Test("Nothing-was-moved says something different from a completed reset", arguments: targets)
    func notRunHasItsOwnMessage(target: Target) {
        // Compare messages so the assertion holds in every localization.
        #expect(Status.notRun.message != Status.success(target).message)
        #expect(Status.notRun.message != Status.partialFailure(0).message)
    }

    // MARK: A reset that ran

    @Test("Zero items left behind is the clean sweep, and keeps its target", arguments: targets)
    func noFailuresIsSuccess(target: Target) {
        let status = Status.completed(target: target, failures: 0)

        #expect(status == .success(target))
        #expect(!status.isError)
    }

    @Test("Each target names its own section in the success message")
    func successMessagesAreDistinctPerTarget() {
        let messages = Set(Self.targets.map { Status.success($0).message })
        #expect(messages.count == Self.targets.count, "A reset must say where the items went")
    }

    @Test("Items left behind are reported with their count", arguments: [1, 2, 17])
    func failuresBecomePartialFailure(count: Int) {
        let status = Status.completed(target: .hidden, failures: count)

        #expect(status == .partialFailure(count))
        #expect(status.isError)
    }

    // MARK: Every other error

    @Test(
        "A reset error that is not the missing engine stays a reported failure",
        arguments: [
            MenuBarItemManager.LayoutResetError.missingAppState,
            MenuBarItemManager.LayoutResetError.missingControlItems,
        ]
    )
    func otherResetErrorsAreFailures(error: MenuBarItemManager.LayoutResetError) {
        let status = Status.thrown(error)

        #expect(status == .failure(error.localizedDescription))
        #expect(status != .notRun, "Only the missing engine means nothing was attempted")
        #expect(status.isError)
    }

    @Test("An error from outside the reset is carried through verbatim")
    func foreignErrorsAreCarried() {
        let error = CocoaError(.fileNoSuchFile)

        #expect(Status.thrown(error) == .failure(error.localizedDescription))
    }

    // MARK: What VoiceOver hears

    @Test("Every outcome but a carried error message is spoken")
    func announcedOutcomes() {
        #expect(Status.success(.hidden).isAnnounced)
        #expect(Status.notRun.isAnnounced, "A user who cannot see the pill still has to learn nothing moved")
        #expect(Status.partialFailure(3).isAnnounced)
        #expect(!Status.failure("disk full").isAnnounced)
    }
}
