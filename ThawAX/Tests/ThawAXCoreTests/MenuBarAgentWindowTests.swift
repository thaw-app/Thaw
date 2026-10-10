//
//  MenuBarAgentWindowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import ThawAXCore

struct MenuBarAgentWindowTests {
    private func entry(_ pid: pid_t, x: CGFloat = 100, width: CGFloat = 24) -> MenuBarAgentWindow.Entry {
        .init(ownerPID: pid, frame: CGRect(x: x, y: 0, width: width, height: 30))
    }

    @Test
    func `names each app once, however many items it has on the bar`() {
        let owners = MenuBarAgentWindow.drawnOwners(in: [entry(10), entry(10, x: 140), entry(20), entry(30)])
        #expect(owners == [10, 20, 30])
    }

    @Test
    func `counts a one point divider as drawn`() {
        #expect(MenuBarAgentWindow.drawnOwners(in: [entry(10, width: 1), entry(20)]) == [10, 20])
    }

    @Test
    func `refuses a read holding the empty child a departing item leaves behind`() {
        let leaving = MenuBarAgentWindow.Entry(ownerPID: 1, frame: .zero)
        #expect(MenuBarAgentWindow.drawnOwners(in: [entry(10), leaving, entry(20)]) == nil)
    }

    @Test
    func `refuses an empty read`() {
        #expect(MenuBarAgentWindow.drawnOwners(in: []) == nil)
    }
}
