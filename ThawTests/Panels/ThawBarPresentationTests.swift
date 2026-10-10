//
//  ThawBarPresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Thaw Bar presentation", .serialized)
struct ThawBarPresentationTests {
    @Test("A cold first show produces an onscreen panel without reopening")
    func coldFirstShow() async throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        let panel = ThawBarPanel()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            panel.close()
            NSApp.setActivationPolicy(originalPolicy)
        }
        NSApp.setActivationPolicy(.accessory)
        panel.performSetup(with: appState)
        // This test asserts on a panel that stays up. The dismissal monitor is
        // global, so a click anywhere, any app on the machine running the
        // suite, would close the panel between the show and the assertions.
        panel.dismissesOnOutsideClick = false
        panel.show(section: .hidden, on: screen)
        #expect(screen.visibleFrame.contains(panel.frame), "The first show must be placed before ordering front: \(panel.frame)")
        try await Task.sleep(for: .milliseconds(350))
        #expect(appState.navigationState.isThawBarPresented)
        #expect(panel.isVisible)
        #expect(panel.frame.width > 0 && panel.frame.height > 0)
        #expect(screen.visibleFrame.contains(panel.frame), "Reported open, but outside the visible display: \(panel.frame)")

        // The retained hosting view must still be placed when its size hasn't changed.
        panel.close()
        panel.setFrameOrigin(NSPoint(x: screen.frame.maxX, y: screen.frame.maxY))
        panel.show(section: .hidden, on: screen)
        #expect(panel.isVisible)
        #expect(screen.visibleFrame.contains(panel.frame), "Reopening must restore onscreen placement: \(panel.frame)")
    }
}
