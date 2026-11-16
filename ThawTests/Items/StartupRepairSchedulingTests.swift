//
//  StartupRepairSchedulingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct StartupRepairSchedulingTests {
    @Test func startupRestrictionChangesDoNotQueueRepairs() {
        let manager = MenuBarItemManager()
        manager.barSettling.holdForTesting()
        defer {
            manager.barSettling.releaseForTesting()
            manager.restrictionRepairSchedule.task?.cancel()
        }

        manager.noteRestrictionChange()
        manager.noteRestrictionChange()

        #expect(manager.restrictionRepairSchedule.task == nil)
    }

    @Test func startupNormalizationDoesNotQueueARewrite() {
        let manager = MenuBarItemManager()
        manager.barSettling.holdForTesting()
        defer {
            manager.barSettling.releaseForTesting()
            manager.structuralNormalizationTask?.cancel()
        }

        manager.scheduleStructuralNormalization(cause: .settled)

        #expect(manager.structuralNormalizationTask == nil)
    }

    @Test func settledStartupCanScheduleRepairsAgain() {
        let manager = MenuBarItemManager()
        manager.barSettling.holdForTesting()
        manager.noteRestrictionChange()
        manager.barSettling.releaseForTesting()
        defer {
            manager.restrictionRepairSchedule.task?.cancel()
            manager.structuralNormalizationTask?.cancel()
        }

        manager.noteRestrictionChange()
        manager.scheduleStructuralNormalization(cause: .settled)

        #expect(manager.restrictionRepairSchedule.task != nil)
        #expect(manager.structuralNormalizationTask != nil)
    }
}
