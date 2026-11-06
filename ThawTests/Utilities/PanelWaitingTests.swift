//
//  PanelWaitingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Waiting for a panel to close, on a one-point transparent panel placed far off every screen.
@MainActor
@Suite("Waiting for a panel to close", .serialized, .timeLimit(.minutes(1)))
struct PanelWaitingTests {
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: -20000, y: -20000, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    @Test("A panel that isn't on screen needs no wait")
    func alreadyClosed() async {
        let panel = makePanel()
        let start = ContinuousClock.now
        await panel.waitUntilClosed(timeout: .seconds(30))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("The wait ends when the panel is ordered out")
    func endsOnClose() async {
        let panel = makePanel()
        panel.orderFrontRegardless()
        #expect(panel.isVisible)

        Task { @MainActor in
            panel.orderOut(nil)
        }
        let start = ContinuousClock.now
        await panel.waitUntilClosed(timeout: .seconds(30))

        #expect(!panel.isVisible)
        #expect(ContinuousClock.now - start < .seconds(25), "it ended on the close, not the timeout")
    }

    @Test("A panel that stays up ends the wait at the timeout")
    func endsOnTimeout() async {
        let panel = makePanel()
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        await panel.waitUntilClosed(timeout: .milliseconds(50))
        #expect(panel.isVisible)
    }
}
