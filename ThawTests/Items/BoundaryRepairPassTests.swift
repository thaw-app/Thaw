//
//  BoundaryRepairPassTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Boundary repair pass")
struct BoundaryRepairPassTests {
    private func item(_ title: String, x: CGFloat = 100) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("test.repair"), title: title),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("An attempted strand is not attempted again but still requests another pass")
    func partialMoveStillNeedsRetry() throws {
        var pass = BoundaryRepairPass()
        let before = item("Battery")
        try pass.recordAttempt(#require(pass.next(in: [before])))

        // A fresh AX read shows slight movement, but the item still sits left
        // of the divider. The caller supplies it as an unsuppressed strand.
        let after = item("Battery", x: 104)
        #expect(pass.next(in: [after]) == nil)
        #expect(pass.needsRetry(in: [after]))
        #expect(pass.attempted.count == 1)
    }

    @Test("A failed item does not consume another item's attempt")
    func eachItemGetsOneAttempt() throws {
        let first = item("Battery")
        let second = item("VPN", x: 150)
        var pass = BoundaryRepairPass()
        try pass.recordAttempt(#require(pass.next(in: [first, second])))
        let next = try #require(pass.next(in: [first, second]))
        #expect(next.uniqueIdentifier == second.uniqueIdentifier)
        pass.recordAttempt(next)
        #expect(pass.next(in: [first, second]) == nil)
        #expect(pass.needsRetry(in: [first, second]))
    }

    @Test("Cleared or suppressed strands do not request another pass")
    func noOutstandingStrandsStopsRetry() {
        var pass = BoundaryRepairPass()
        pass.recordAttempt(item("Battery"))
        // The caller removes repaired and breaker-suppressed items from its
        // fresh strand list before asking whether another pass is needed.
        #expect(!pass.needsRetry(in: []))
    }

    @Test("A declined pass does not start a retry loop")
    func noAttemptDoesNotRetry() {
        let pass = BoundaryRepairPass()
        #expect(!pass.needsRetry(in: [item("Battery")]))
    }
}
