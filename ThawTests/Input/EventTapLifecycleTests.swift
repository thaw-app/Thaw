//
//  EventTapLifecycleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Event tap lifecycle", .serialized, .enabled(if: CGPreflightListenEventAccess(), "Requires event-listening access"))
struct EventTapLifecycleTests {
    @Test("A new tap is disabled until its run-loop source is attached")
    func initiallyDisabled() throws {
        let tap = EventTap(
            label: "initiallyDisabledTest",
            type: .mouseMoved,
            location: .sessionEventTap,
            placement: .headInsertEventTap,
            option: .listenOnly
        ) { _, event in event }
        defer { tap.invalidate() }
        try #require(tap.isValid)
        #expect(!tap.isEnabled)

        // This is the conditional startup used by the Clock/shortcut bridge.
        if tap.ensureValid(), !tap.isEnabled {
            tap.enable()
        }
        #expect(tap.isEnabled)
        tap.disable()
        #expect(!tap.isEnabled)
        tap.enable()
        #expect(tap.isEnabled)
        tap.invalidate()
        #expect(!tap.isValid)
        #expect(!tap.isEnabled)
        #expect(!tap.ensureValid())
    }
}
