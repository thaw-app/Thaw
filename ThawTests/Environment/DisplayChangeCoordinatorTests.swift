//
//  DisplayChangeCoordinatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

@Suite("Display change plan")
struct DisplayChangePlanTests {
    @Test(
        "A change that keeps every display stamps and starts the settle, with nothing to wait for after it",
        arguments: [
            (EnvironmentChange.displayAdded, "displayConnect"),
            (.rearranged, "displayArrangement"),
            (.resolutionOnly, "displayArrangement"),
        ]
    )
    func stepsPerChange(change: EnvironmentChange, reason: String) {
        #expect(DisplayChangePlan.steps(for: change) == [
            .stampDisplayChanged,
            .startSettle(reason: reason),
        ])
    }

    @Test("A removed display also waits out the settle, then cleans the stale images")
    func removedDisplayCleansImages() {
        #expect(DisplayChangePlan.steps(for: .displayRemoved) == [
            .stampDisplayChanged,
            .startSettle(reason: "displayDisconnect"),
            .awaitSettle,
            .cleanImages,
        ])
    }

    @Test("Only a removed display cleans images")
    func onlyRemovalCleansImages() {
        for change in [EnvironmentChange.displayAdded, .rearranged, .resolutionOnly, .none] {
            #expect(!DisplayChangePlan.steps(for: change).contains(.cleanImages))
        }
    }

    @Test("An unchanged settle plans nothing")
    func unchangedPlansNothing() {
        #expect(DisplayChangePlan.steps(for: .none).isEmpty)
    }

    @Test("Each plan stamps the display change exactly once")
    func stampsOnce() {
        for change in [EnvironmentChange.displayAdded, .displayRemoved, .rearranged, .resolutionOnly] {
            #expect(DisplayChangePlan.steps(for: change).count(where: { $0 == .stampDisplayChanged }) == 1)
        }
    }
}

@MainActor
@Suite("Display change coordinator", .timeLimit(.minutes(1)))
struct DisplayChangeCoordinatorTests {
    private static let single = DisplayArrangement(frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982)], mainDisplayID: 1)
    private static let docked = DisplayArrangement(
        frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982), 2: CGRect(x: 1512, y: 0, width: 2560, height: 1440)],
        mainDisplayID: 1
    )

    @Test("A burst of postings runs each step once, in order")
    func burstRunsEachStepOnce() async {
        let center = NotificationCenter()
        let environment = DisplayEnvironment(
            center: center,
            baseline: Self.single,
            read: { Self.docked },
            sleep: { _ in
                try Task.checkCancellation()
                await Task.yield()
                try Task.checkCancellation()
            }
        )
        let effects = RecordingEffects()
        let coordinator = DisplayChangeCoordinator(environment: environment, effects: effects)
        coordinator.start()
        environment.start()
        defer {
            environment.stop()
            coordinator.stop()
        }

        for _ in 0 ..< 5 {
            center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        await environment.waitUntilSettled()
        await coordinator.waitUntilIdle()

        #expect(effects.steps == [
            .stampDisplayChanged,
            .startSettle(reason: "displayConnect"),
        ])
    }

    @Test("A newer generation mid-run abandons the rest and runs the new one's steps")
    func newerGenerationRestarts() async {
        let harness = CoordinatorHarness(baseline: Self.docked)
        harness.effects.holdsSettle = true

        harness.settle(on: Self.single)
        await harness.effects.waitForHeldSettles(1)
        harness.settle(on: Self.docked)
        await harness.coordinator.waitUntilIdle()
        harness.effects.releaseSettles()
        await harness.effects.waitForReturnedSettles(1)

        #expect(harness.effects.steps == [
            .stampDisplayChanged,
            .startSettle(reason: "displayDisconnect"),
            .awaitSettle,
            .stampDisplayChanged,
            .startSettle(reason: "displayConnect"),
        ])
    }

    @Test("An unchanged settle runs nothing")
    func unchangedSettleRunsNothing() async {
        let harness = CoordinatorHarness(baseline: Self.single)

        harness.settle(on: Self.single)
        await harness.coordinator.waitUntilIdle()

        #expect(harness.effects.steps.isEmpty)
    }

    @Test("Each run asks for the display change once")
    func eachRunStampsOnce() async {
        let harness = CoordinatorHarness(baseline: Self.single)

        harness.settle(on: Self.docked)
        await harness.coordinator.waitUntilIdle()
        #expect(harness.effects.steps.count(where: { $0 == .stampDisplayChanged }) == 1)

        harness.settle(on: Self.single)
        await harness.coordinator.waitUntilIdle()
        #expect(harness.effects.steps.count(where: { $0 == .stampDisplayChanged }) == 2)
        #expect(harness.effects.steps.last == .cleanImages)
    }

    @Test("A stopped coordinator ignores later settles")
    func stoppedIgnoresSettles() async {
        let harness = CoordinatorHarness(baseline: Self.single)
        harness.coordinator.stop()

        harness.settle(on: Self.docked)
        await harness.coordinator.waitUntilIdle()

        #expect(harness.effects.steps.isEmpty)
    }
}

@MainActor
@Suite("Menu bar display change effects", .timeLimit(.minutes(1)))
struct MenuBarDisplayChangeEffectsTests {
    @Test("The stamp calls off the automatic passes planned before the change")
    func stampCallsOffPlannedWork() {
        let manager = MenuBarItemManager()
        let effects = MenuBarDisplayChangeEffects(itemManager: manager, repairs: manager.repairs, imageCache: MenuBarItemImageCache())
        manager.repairs.request(.overflowRebalance, cause: .cachePublished)

        effects.stampDisplayChanged()

        #expect(manager.repairs.ledger.causesWaiting(for: .overflowRebalance).isEmpty)
    }

    @Test("Waiting for the settle returns at once when none is running")
    func awaitWithoutSettle() async {
        let manager = MenuBarItemManager()
        let effects = MenuBarDisplayChangeEffects(itemManager: manager, repairs: manager.repairs, imageCache: MenuBarItemImageCache())

        await effects.awaitSettle()

        #expect(!manager.isInStartupSettling)
    }

    @Test("Waiting for the settle follows a replaced settling task to the end")
    func awaitFollowsReplacedSettle() async {
        let manager = MenuBarItemManager()
        let effects = MenuBarDisplayChangeEffects(itemManager: manager, repairs: manager.repairs, imageCache: MenuBarItemImageCache())
        let finished = Flag()
        let replacement = Task { @MainActor in
            await Task.yield()
            finished.value = true
            manager.isInStartupSettling = false
        }
        manager.isInStartupSettling = true
        manager.startupSettlingTask = Task { @MainActor in
            await Task.yield()
            manager.startupSettlingTask = replacement
        }

        await effects.awaitSettle()

        #expect(finished.value)
    }
}

@MainActor
private final class Flag {
    var value = false
}

@MainActor
private final class CoordinatorHarness {
    let snapshot: EnvironmentSnapshot
    let effects = RecordingEffects()
    let coordinator: DisplayChangeCoordinator
    private let settlements = PassthroughSubject<EnvironmentChange, Never>()

    init(baseline: DisplayArrangement) {
        snapshot = EnvironmentSnapshot(arrangement: baseline)
        coordinator = DisplayChangeCoordinator(snapshot: snapshot, settlements: settlements, effects: effects)
        coordinator.start()
    }

    func settle(on arrangement: DisplayArrangement) {
        settlements.send(snapshot.settle(on: arrangement))
    }
}

/// Records each step, and can hold the settle wait open until the test releases it.
@MainActor
private final class RecordingEffects: DisplayChangeEffects {
    private(set) var steps: [DisplayChangeStep] = []
    var holdsSettle = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldCount = 0
    private var returnedCount = 0

    func stampDisplayChanged() {
        steps.append(.stampDisplayChanged)
    }

    func startSettle(reason: String) {
        steps.append(.startSettle(reason: reason))
    }

    func awaitSettle() async {
        steps.append(.awaitSettle)
        if holdsSettle {
            heldCount += 1
            await withCheckedContinuation { held.append($0) }
        }
        returnedCount += 1
    }

    func cleanImagesAfterRemoval() async {
        steps.append(.cleanImages)
    }

    func releaseSettles() {
        holdsSettle = false
        let waiting = held
        held.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

    func waitForHeldSettles(_ count: Int) async {
        while heldCount < count {
            await Task.yield()
        }
    }

    func waitForReturnedSettles(_ count: Int) async {
        while returnedCount < count {
            await Task.yield()
        }
    }
}
