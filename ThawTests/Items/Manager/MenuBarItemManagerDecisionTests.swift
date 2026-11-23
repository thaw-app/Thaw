//
//  MenuBarItemManagerDecisionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Which app launches hold the move pass until their item re-pairs. Each launch is weighed as it
/// arrives, so a tracked relaunch followed within the second by another app still settles the bar.
@Suite("App launch settle")
struct AppLaunchSettleTests {
    private static let known: Set<String> = ["com.example.tracked:Item-0", "com.example.other-tracked:Clock"]

    @Test("A relaunch of an app Thaw tracks an item for settles on its bundle ID")
    func trackedAppSettles() {
        #expect(MenuBarItemManager.launchSettle(bundleID: "com.example.tracked", knownIdentifiers: Self.known)
            == .appLaunched(bundleID: "com.example.tracked"))
    }

    @Test("An app with no tracked item, or with no bundle ID, starts no settle")
    func untrackedAppDoesNotSettle() {
        #expect(MenuBarItemManager.launchSettle(bundleID: "com.example.unrelated", knownIdentifiers: Self.known) == nil)
        #expect(MenuBarItemManager.launchSettle(bundleID: nil, knownIdentifiers: Self.known) == nil)
    }

    @Test("A bundle ID that only starts like a tracked one isn't taken for it")
    func prefixIsNotAMatch() {
        #expect(MenuBarItemManager.launchSettle(bundleID: "com.example.track", knownIdentifiers: Self.known) == nil)
    }
}

/// A partial scan publishes the cache but leaves the saved-order mirror and overflow balancing to a
/// complete one, which still owes them when it finds the same cache.
@Suite("Partial scan follow-up")
struct PartialScanFollowUpTests {
    @Test("A complete scan that finds a partial scan's cache unchanged runs the work it left")
    func completeScanRunsDeferredWork() {
        #expect(MenuBarItemManager.unchangedCacheOwesDeferredWork(observationOnly: false, awaitsFullScan: true))
    }

    @Test("An unchanged cache owes nothing after a complete scan, and a partial scan never runs the work")
    func nothingOwed() {
        #expect(!MenuBarItemManager.unchangedCacheOwesDeferredWork(observationOnly: false, awaitsFullScan: false))
        #expect(!MenuBarItemManager.unchangedCacheOwesDeferredWork(observationOnly: true, awaitsFullScan: true))
    }
}

/// A pending visible edit is retired only from a read that has the items it orders.
@Suite("Order confirmation coverage")
struct OrderConfirmationCoverageTests {
    private static func item(_ bundleID: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", windowID: 1),
            windowID: 1,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    private static let a = item("com.example.a")
    private static let b = item("com.example.b")
    private static let order = [a.uniqueIdentifier, b.uniqueIdentifier]

    @Test("A read that missed one of the ordered items the cache has can't confirm the order")
    func shortReadIsMissing() {
        let missed = MenuBarItemManager.desiredItemsMissing(from: [Self.a], desiredOrder: Self.order, cached: [Self.a, Self.b])
        #expect(missed == [Self.b.uniqueIdentifier])
    }

    @Test("A read with every ordered item is complete")
    func fullReadIsComplete() {
        #expect(MenuBarItemManager.desiredItemsMissing(from: [Self.b, Self.a], desiredOrder: Self.order, cached: [Self.a, Self.b]).isEmpty)
    }

    @Test("An ordered item the cache doesn't have either, such as a closed app's, isn't expected")
    func closedAppIsNotExpected() {
        #expect(MenuBarItemManager.desiredItemsMissing(from: [Self.a], desiredOrder: Self.order, cached: [Self.a]).isEmpty)
    }
}

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

/// A restriction reflow moves every item for a moment, so the saved layout is not laid back over it.
@MainActor
@Suite("Saved layout during a restriction reflow", .scratchDefaults)
struct RestrictionReflowLayoutTests {
    private static let hidden = MenuBarItem(
        tag: .hiddenControlItem,
        windowID: 9,
        ownerPID: 501,
        sourcePID: 501,
        bounds: CGRect(x: 1500, y: 4.5, width: 2, height: 24),
        title: ControlItemIdentifier.hidden.rawValue,
        isOnScreen: true
    )

    @Test("The saved layout stands down inside the reflow window and asks to be tried again")
    func savedLayoutWaitsOutTheReflow() async {
        let manager = MenuBarItemManager()
        defer { manager.restrictionRepairSchedule.task?.cancel() }
        manager.savedSectionOrder = [MenuBarSectionName.visible.rawValue: ["com.example.one"]]

        manager.noteRestrictionChange()
        let applied = await manager.applySavedLayout(
            items: [],
            previousWindowIDs: [],
            controlItems: ControlItemPair(hidden: Self.hidden, alwaysHidden: nil)
        )

        #expect(!applied)
        #expect(manager.repairs.ledger.causesWaiting(for: .deferredLayoutReconcile) == [.layoutApplyBlocked])
    }
}

/// Pressing a hidden item shows it first. Handing that reveal back must leave an item a module holds shown.
@MainActor
@Suite("Press reveal hand-back")
struct PressRevealHandBackTests {
    private let identifier = "com.example:Item-0"

    private func holds(holding: Bool) -> HeldItemReveals {
        let holds = HeldItemReveals(reveal: { _ in }, conceal: { _ in })
        if holding {
            holds.hold(identifier, for: "triggers")
        }
        return holds
    }

    @Test("A press that opened the menu schedules the conceal, and a failed one conceals at once")
    func unheldItemIsHandedBack() {
        let controller = RecordingSectionController()
        MenuBarItemManager.handBackPressReveal(identifier, pressed: true, controller: controller, holds: holds(holding: false))
        MenuBarItemManager.handBackPressReveal(identifier, pressed: false, controller: controller, holds: holds(holding: false))

        #expect(controller.scheduledConceals == [identifier])
        #expect(controller.immediateConceals == [identifier])
    }

    @Test("A held item stays shown whether the press opened its menu or not")
    func heldItemStaysShown() {
        let controller = RecordingSectionController()
        MenuBarItemManager.handBackPressReveal(identifier, pressed: true, controller: controller, holds: holds(holding: true))
        MenuBarItemManager.handBackPressReveal(identifier, pressed: false, controller: controller, holds: holds(holding: true))

        #expect(controller.scheduledConceals.isEmpty)
        #expect(controller.immediateConceals.isEmpty)
    }
}
