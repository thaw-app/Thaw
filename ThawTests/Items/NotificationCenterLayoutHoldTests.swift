//
//  NotificationCenterLayoutHoldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Layout work is held while Notification Center opens, and released by the settle that is still current")
struct NotificationCenterLayoutHoldTests {
    /// A settle that never ends, so a test decides for itself when the wait is over.
    private func pendingSettle(_: UUID?) -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(3600)) }
    }

    @Test("Nothing is held or settling to begin with")
    func startsIdle() {
        let hold = NotificationCenterLayoutHold()

        #expect(!hold.isHeld)
        #expect(!hold.isSettling)
    }

    @Test("The first begin takes the hold, and a second one only renews it")
    func beginTakesThenRenews() {
        var hold = NotificationCenterLayoutHold()

        let first = hold.begin()
        let second = hold.begin()

        #expect(first)
        #expect(!second)
        #expect(hold.isHeld)
    }

    @Test("A settle is handed the token of the hold it ends, and stays held while it waits")
    func settleReceivesTheCurrentToken() {
        var hold = NotificationCenterLayoutHold()
        hold.begin()
        var handed: UUID?

        let task = hold.settle { token in
            handed = token
            return pendingSettle(token)
        }
        defer { task.cancel() }

        #expect(handed != nil)
        #expect(hold.isHeld)
        #expect(hold.isSettling)
    }

    @Test("The settle that is still current releases the hold")
    func currentSettleReleases() {
        var hold = NotificationCenterLayoutHold()
        hold.begin()
        var handed: UUID?
        let task = hold.settle { token in
            handed = token
            return pendingSettle(token)
        }
        defer { task.cancel() }

        let released = hold.release(ifCurrent: handed)

        #expect(released)
        #expect(!hold.isHeld)
        #expect(!hold.isSettling)
    }

    @Test("A begin during the settle cancels it, and its token no longer releases anything")
    func beginSupersedesThePendingSettle() {
        var hold = NotificationCenterLayoutHold()
        hold.begin()
        var stale: UUID?
        let task = hold.settle { token in
            stale = token
            return pendingSettle(token)
        }

        let renewed = hold.begin()

        #expect(!renewed)
        #expect(task.isCancelled)
        #expect(!hold.isSettling)
        let released = hold.release(ifCurrent: stale)
        #expect(!released)
        #expect(hold.isHeld)
    }

    @Test("A second settle cancels the first, and both carry the same token")
    func laterSettleReplacesTheEarlier() {
        var hold = NotificationCenterLayoutHold()
        hold.begin()
        var tokens: [UUID?] = []
        let first = hold.settle { token in
            tokens.append(token)
            return pendingSettle(token)
        }
        let second = hold.settle { token in
            tokens.append(token)
            return pendingSettle(token)
        }
        defer { second.cancel() }

        #expect(first.isCancelled)
        #expect(!second.isCancelled)
        #expect(tokens.count == 2)
        #expect(tokens.first == tokens.last)
    }

    @Test("A hold released once is not released again by the same token")
    func releaseHappensOnce() {
        var hold = NotificationCenterLayoutHold()
        hold.begin()
        var handed: UUID?
        let task = hold.settle { token in
            handed = token
            return pendingSettle(token)
        }
        defer { task.cancel() }
        hold.release(ifCurrent: handed)

        let again = hold.release(ifCurrent: handed)

        #expect(!again)
    }

    @Test("A settle with nothing held is handed no token and releases nothing")
    func settleWithoutBeginReleasesNothing() {
        var hold = NotificationCenterLayoutHold()
        var handed: UUID? = UUID()
        let task = hold.settle { token in
            handed = token
            return pendingSettle(token)
        }
        defer { task.cancel() }

        #expect(handed == nil)
        let released = hold.release(ifCurrent: handed)
        #expect(!released)
        #expect(!hold.isHeld)
        #expect(hold.isSettling)
    }
}

@Suite("Notification Center layout suspension")
@MainActor
struct NotificationCenterLayoutSuspensionTests {
    @Test("Assertion changes cannot schedule repair or publish temporary geometry")
    func suspensionBlocksRepairAndPublication() async {
        let manager = MenuBarItemManager()
        defer { manager.restrictionRepairSchedule.task?.cancel() }
        manager.noteRestrictionChange()
        #expect(manager.restrictionRepairSchedule.task != nil)
        let before = manager.layoutPublication.generation
        manager.beginNotificationCenterLayoutSuspension()
        manager.noteRestrictionChange()
        manager.scheduleStructuralNormalization(cause: .restrictionChanged)
        #expect(manager.restrictionRepairSchedule.task == nil)
        #expect(manager.structuralNormalizationTask == nil)
        #expect(!manager.layoutPublication.canPublish(generation: before))
        #expect(!manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))

        let restore = manager.endNotificationCenterLayoutSuspension(settle: {})
        #expect(manager.isNotificationCenterLayoutSuspended)
        await restore.value
        #expect(!manager.isNotificationCenterLayoutSuspended)
        #expect(manager.restrictionRepairSchedule.task != nil)
        #expect(manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))
        #expect(!manager.layoutPublication.canPublish(generation: before))
    }

    @Test("A rapid second toggle cannot be unlocked by the first restore")
    func repeatedToggleSupersedesRestore() async {
        let manager = MenuBarItemManager()
        manager.beginNotificationCenterLayoutSuspension()
        let firstRestore = manager.endNotificationCenterLayoutSuspension(settle: {})
        manager.beginNotificationCenterLayoutSuspension()
        await firstRestore.value
        #expect(manager.isNotificationCenterLayoutSuspended)
        #expect(!manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))
        await manager.endNotificationCenterLayoutSuspension(settle: {}).value
        #expect(manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))
    }

    @Test("Restoring Notification Center does not release another layout mutation")
    func unrelatedMutationRemainsHeld() async {
        let manager = MenuBarItemManager()
        manager.layoutPublication.beginMutation()
        manager.beginNotificationCenterLayoutSuspension()
        await manager.endNotificationCenterLayoutSuspension(settle: {}).value
        #expect(!manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))
        manager.layoutPublication.endMutation()
        #expect(manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))
    }
}
