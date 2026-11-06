//
//  WindowServerIDTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Window server IDs")
struct WindowServerIDTests {
    @Test("A window number in CGWindowID range converts")
    func validWindowNumber() {
        #expect(NSWindow.windowServerID(forWindowNumber: 2_652_381_101) == 2_652_381_101)
        #expect(NSWindow.windowServerID(forWindowNumber: Int(UInt32.max)) == UInt32.max)
    }

    @Test("Zero, negative and synthetic window numbers have no ID", arguments: [
        0, -1, 0x8_0000_0000, 0x9_0000_0000, Int(UInt32.max) + 1, Int.max,
    ])
    func invalidWindowNumbers(_ windowNumber: Int) {
        #expect(NSWindow.windowServerID(forWindowNumber: windowNumber) == nil)
    }
}
