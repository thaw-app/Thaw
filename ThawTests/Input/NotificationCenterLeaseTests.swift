//
//  NotificationCenterLeaseTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("The Notification Center bridge holds one release lease at a time")
struct NotificationCenterLeaseTests {
    @Test("A second press while the lease is held takes no new lease and restores once")
    func secondPrepareReusesTheLease() async {
        var begins = 0
        var restores = 0
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { false })

        for _ in 0 ..< 2 {
            bridge.prepareLease(begin: { begins += 1; return .acquired }, restore: { restores += 1 })
        }
        #expect(begins == 1)
        await bridge.waitUntilIdle()

        #expect(restores == 1)
        #expect(!bridge.isBusy)
    }

    @Test("A press that needs no release holds nothing and restores nothing")
    func notRequiredHoldsNothing() async {
        var restores = 0
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { false })

        bridge.prepareLease(begin: { .notRequired }, restore: { restores += 1 })

        #expect(!bridge.isBusy)
        await bridge.waitUntilIdle()
        #expect(restores == 0)
    }

    @Test("A request queued while the lease is held re-reads the panel, so a close gesture restores on dismissal")
    func enqueueUnderAHeldLease() async {
        var delivered: [NotificationCenterActivation.Request] = []
        var outcomes: [NotificationCenterActivation.Outcome] = []
        var restores = 0
        var isPresenting = false
        let request = NotificationCenterActivation.Request.clock(CGPoint(x: 10, y: 5))
        let bridge = NotificationCenterActivation(
            activate: { delivered.append($0); isPresenting = false },
            panelPresenting: { isPresenting },
            report: { outcomes.append($0) }
        )

        bridge.prepareLease(begin: { .acquired }, restore: { restores += 1 })
        // The panel was already up when the click that closes it arrived.
        isPresenting = true
        bridge.enqueue(request)
        await bridge.waitUntilIdle()

        #expect(delivered == [request])
        #expect(outcomes == [.panelClosed])
        #expect(restores == 1)
        #expect(!bridge.isBusy)
    }
}
