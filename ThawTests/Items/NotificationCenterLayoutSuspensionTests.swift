//
//  NotificationCenterLayoutSuspensionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Notification Center layout suspension")
@MainActor
struct NotificationCenterLayoutSuspensionTests {
    @Test("Assertion changes cannot schedule repair or publish temporary geometry")
    func suspensionBlocksRepairAndPublication() async {
        let manager = MenuBarItemManager()
        manager.isInStartupSettling = false
        defer { manager.postRestrictionRepairTask?.cancel() }
        manager.noteRestrictionChange()
        #expect(manager.postRestrictionRepairTask != nil)
        let before = manager.layoutPublication.generation
        manager.beginNotificationCenterLayoutSuspension()
        manager.noteRestrictionChange()
        manager.scheduleStructuralNormalization(cause: .restrictionChanged)
        #expect(manager.postRestrictionRepairTask == nil)
        #expect(manager.structuralNormalizationTask == nil)
        #expect(!manager.layoutPublication.canPublish(generation: before))
        #expect(!manager.layoutPublication.canPublish(generation: manager.layoutPublication.generation))

        let restore = manager.endNotificationCenterLayoutSuspension(settle: {})
        #expect(manager.isNotificationCenterLayoutSuspended)
        await restore.value
        #expect(!manager.isNotificationCenterLayoutSuspended)
        #expect(manager.postRestrictionRepairTask != nil)
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
