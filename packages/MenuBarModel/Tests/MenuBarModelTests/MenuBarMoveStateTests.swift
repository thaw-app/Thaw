//
//  MenuBarMoveStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SectionTransitionSerializationTests {
    @Test("A second section pre-seat cannot change positions during the first verification")
    func preSeatWaitsForVerificationAndCommit() async throws {
        let gate = SimpleSemaphore(value: 1)
        let firstWritten = AsyncStream.makeStream(of: Void.self)
        let secondRequested = AsyncStream.makeStream(of: Void.self)
        var cleanShotWeight = 798
        var cleanShotAssigned = false
        var secondSawCommittedAssignment = false

        let cleanShot = Task {
            try await gate.withPermit {
                cleanShotWeight = 389
                firstWritten.continuation.yield(())
                firstWritten.continuation.finish()
                for await _ in secondRequested.stream {
                    break
                }
                #expect(cleanShotWeight == 389, "AdGuard must not re-space CleanShot before verification")
                cleanShotAssigned = true
            }
        }
        for await _ in firstWritten.stream {
            break
        }
        let adGuard = Task {
            secondRequested.continuation.yield(())
            secondRequested.continuation.finish()
            try await gate.withPermit {
                secondSawCommittedAssignment = cleanShotAssigned
                cleanShotWeight = 799
            }
        }
        try await cleanShot.value
        try await adGuard.value
        #expect(secondSawCommittedAssignment)
        #expect(cleanShotWeight == 799)
    }

    @Test("A failed move releases its permit for the next section transition")
    func failureReleasesPermit() async throws {
        enum MoveFailure: Error { case verification }
        let gate = SimpleSemaphore(value: 1)
        await #expect(throws: MoveFailure.verification) {
            try await gate.withPermit { throw MoveFailure.verification }
        }
        let committed = try await gate.withPermit { true }
        #expect(committed)
    }

    @Test("Cancellation during verification releases the permit without committing")
    func cancelledVerificationReleasesPermit() async throws {
        let gate = SimpleSemaphore(value: 1)
        let started = AsyncStream.makeStream(of: Void.self)
        let verification = AsyncStream.makeStream(of: Void.self)
        var committed = false
        let request = Task {
            try await gate.withPermit {
                started.continuation.yield(())
                started.continuation.finish()
                for await _ in verification.stream {
                    break
                }
                try Task.checkCancellation()
                committed = true
            }
        }
        for await _ in started.stream {
            break
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(!committed)
        let nextCommitted = try await gate.withPermit { true }
        #expect(nextCommitted)
    }

    @Test("A cancelled request does not pre-seat or consume the active move's permit")
    func cancellationDoesNotMutate() async throws {
        let gate = SimpleSemaphore(value: 1)
        try await gate.wait()
        var wrotePositions = false
        let request = Task {
            try await gate.withPermit { wrotePositions = true }
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(!wrotePositions)
        await gate.signal()
        let committed = try await gate.withPermit { true }
        #expect(committed)
    }
}

@Suite("Move operation tracker")
@MainActor
struct MoveOperationTrackerTests {
    @Test("A fresh tracker reports nothing")
    func freshTrackerIsQuiet() {
        let tracker = MoveOperationTracker()
        #expect(!tracker.occurred(within: .seconds(60)))
        #expect(!tracker.isInFlight)
        #expect(tracker.lastInstant == nil)
    }

    @Test("A stamp counts as recent without stamping an in-flight window")
    func stampIsRecent() {
        let tracker = MoveOperationTracker()
        tracker.noteMoveOperation()
        #expect(tracker.occurred(within: .seconds(1)))
        #expect(!tracker.isInFlight)
    }

    @Test("An in-flight move counts as recent for the whole window, even unstamped")
    func inFlightCountsAsRecent() {
        let tracker = MoveOperationTracker()
        tracker.beginMoveOperation()
        #expect(tracker.isInFlight)
        #expect(tracker.occurred(within: .zero))
        // Begin does not stamp: consumers computing buffers off the last
        // stamp must not see a phantom operation.
        #expect(tracker.lastInstant == nil)
        tracker.endMoveOperation()
        #expect(!tracker.isInFlight)
        #expect(!tracker.occurred(within: .seconds(60)))
    }

    @Test("Nested begins stay in flight until every end")
    func nestedBegins() {
        let tracker = MoveOperationTracker()
        tracker.beginMoveOperation()
        tracker.beginMoveOperation()
        tracker.endMoveOperation()
        #expect(tracker.isInFlight)
        tracker.endMoveOperation()
        #expect(!tracker.isInFlight)
        // An unbalanced end never goes negative and never blocks a later begin.
        tracker.endMoveOperation()
        tracker.beginMoveOperation()
        #expect(tracker.isInFlight)
    }

    @Test("Waiting returns only after the move in flight ends")
    func waitUntilIdleWaitsForTheMove() async {
        let tracker = MoveOperationTracker()
        tracker.beginMoveOperation()
        var returned = false
        let waiter = Task {
            await tracker.waitUntilIdle(pollingEvery: .milliseconds(5))
            returned = true
        }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!returned)
        tracker.endMoveOperation()
        await waiter.value
        #expect(returned)
    }
}

struct MenuBarLayoutPublicationStateTests {
    @Test("A scan started before or during a move cannot publish afterward")
    func movementInvalidatesScans() {
        var state = MenuBarLayoutPublicationState()
        let before = state.generation
        state.beginMutation()
        let during = state.generation
        #expect(!state.canPublish(generation: before))
        #expect(!state.canPublish(generation: during))
        state.endMutation()
        #expect(!state.canPublish(generation: before))
        #expect(!state.canPublish(generation: during))
        #expect(state.canPublish(generation: state.generation))
    }

    @Test("A nested transition retains its publication hold until the last release")
    func nestedMutation() {
        var state = MenuBarLayoutPublicationState()
        state.beginMutation()
        state.beginMutation()
        state.endMutation()
        #expect(!state.canPublish(generation: state.generation))
        state.endMutation()
        #expect(state.canPublish(generation: state.generation))
    }

    @Test("New authored intent invalidates an older scan without starting a move")
    func authoredEdit() {
        var state = MenuBarLayoutPublicationState()
        let before = state.generation
        state.invalidate()
        #expect(!state.canPublish(generation: before))
    }
}

struct MoveDestinationSectionTests {
    private let mover = MenuBarItem.fixture(MenuBarItemTag(namespace: .string("test.app"), title: "Item"))

    @Test("Boundary crossings use the requested side, not the mover's identity", arguments: [
        (MenuBarItemTag.hiddenControlItem, MenuBarSectionName?.some(.hidden), MenuBarSectionName?.some(.visible)),
        (.alwaysHiddenControlItem, .alwaysHidden, .hidden),
        (.visibleControlItem, .visible, nil),
        // An ordinary neighbour is not a section crossing.
        (MenuBarItemTag(namespace: .string("test.other"), title: "Other"), nil, nil),
    ])
    func crossingSides(tag: MenuBarItemTag, left: MenuBarSectionName?, right: MenuBarSectionName?) {
        let anchor = MenuBarItem.fixture(tag)
        #expect(MoveDestination.leftOfItem(anchor).sectionAcrossBoundary(from: mover) == left)
        #expect(MoveDestination.rightOfItem(anchor).sectionAcrossBoundary(from: mover) == right)
    }

    @Test("A rediscovered control cannot be moved across itself")
    func selfTarget() {
        let mover = MenuBarItem.fixture(.hiddenControlItem)
        let anchor = MenuBarItem.fixture(.hiddenControlItem, windowID: 2)
        #expect(MoveDestination.leftOfItem(anchor).sectionAcrossBoundary(from: mover) == nil)
        #expect(MoveDestination.rightOfItem(anchor).sectionAcrossBoundary(from: mover) == nil)
    }
}

/// Section names are Codable, so a changed raw value loses saved layouts.
@Test("Section names keep their order, wire values and labels", arguments: [
    (MenuBarSectionName.visible, "visible", "Visible", "visible section"),
    (.hidden, "hidden", "Hidden", "hidden section"),
    (.alwaysHidden, "alwaysHidden", "Always Hidden", "always-hidden section"),
])
func sectionNameValues(section: MenuBarSectionName, rawValue: String, displayString: String, logString: String) {
    #expect(MenuBarSectionName.allCases == [.visible, .hidden, .alwaysHidden])
    #expect(section.rawValue == rawValue)
    #expect(section.displayString == displayString)
    #expect(section.logString == logString)
}
