//
//  PressRevealHandBackTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

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
