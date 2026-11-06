//
//  NativeOverflowPresenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("macOS's overflow is tracked per display for Settings", .serialized, .scratchDefaults)
struct NativeOverflowPresenceTests {
    @Test("Only connected displays the engine reports count, and the answer follows the engine")
    func followsTheEngine() {
        let presence = NativeOverflowPresence()
        var active: Set<CGDirectDisplayID> = [1, 9]
        presence.refresh(displays: [1, 2]) { active.contains($0) }
        #expect(presence.displayIDs == [1])
        #expect(presence.isPresent(on: 1))
        #expect(!presence.isPresent(on: 2))
        #expect(!presence.isPresent(on: 9))
        presence.refresh(displays: [1, 2]) { active.contains($0) }
        #expect(presence.displayIDs == [1])

        active = []
        presence.refresh(displays: [1, 2]) { active.contains($0) }
        #expect(!presence.isPresent(on: 1))
    }

    @Test("No display means no overflow")
    func noDisplay() {
        let presence = NativeOverflowPresence()
        presence.refresh(displays: [1]) { _ in true }
        #expect(!presence.isPresent(on: nil))
    }

    @Test("The engine's control-item update refreshes it, and nothing reads as overflowing before setup")
    func adapterRefreshes() {
        let appState = AppState()
        let adapter = RuntimeSectionContextAdapter(appState: appState, revealAttribution: RevealAttribution())
        appState.nativeOverflowPresence.refresh(displays: [CGMainDisplayID()]) { _ in true }
        #expect(!appState.nativeOverflowPresence.displayIDs.isEmpty, "seeded directly, so only the adapter's refresh can clear it")
        adapter.updateControlItemStates()
        #expect(appState.nativeOverflowPresence.displayIDs.isEmpty)
    }
}
