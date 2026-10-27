//
//  SwapBarViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import SwiftUI
import Testing
@testable import Thaw

/// The Swap Bar's panel and contents, built off screen against a fresh app state and throwaway settings.
@Suite("Swap Bar view and panel", .serialized, .scratchDefaults)
@MainActor
struct SwapBarViewTests {
    @Test("The panel is a key-capable, non-activating floating strip that never becomes main")
    func panelConfiguration() {
        let panel = SwapBarPanel()
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(!panel.isOpaque)
        #expect(!panel.hasShadow)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.fittingContentSize == .zero, "an empty content view asks for no room")
    }

    @Test("Presenting twice reuses the hosting view and sizes the panel to the bar")
    func presentReusesHost() throws {
        let appState = AppState()
        let panel = SwapBarPanel()
        panel.present(SwapBarView(appState: appState))
        let host = try #require(panel.contentView)
        #expect(host.acceptsFirstMouse(for: nil), "a press acts before the panel is key")

        panel.present(SwapBarView(appState: appState))
        #expect(panel.contentView === host)

        let size = panel.fittingContentSize
        #expect(size.width > 200)
        #expect(size.height > 30)
    }

    @Test("Escape on a panel that is not key leaves it alone")
    func cancelWhenNotKey() {
        let panel = SwapBarPanel()
        panel.cancelOperation(nil)
        #expect(!panel.isVisible)
    }

    @Test("The bar draws, and redraws when the swap state's label changes")
    func barDraws() throws {
        let appState = AppState()
        let view = SwapBarView(appState: appState)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        #expect(size.width > size.height, "the bar is a horizontal strip")
        let render = OffscreenRender(view, size: size)
        #expect(try render.pixels().contains { $0 != 0 })
    }

    @Test("A section state change reaches the view's stored publisher")
    func sectionChangesPublisher() async {
        let appState = AppState()
        let view = SwapBarView(appState: appState)
        var received = 0
        let cancellable = view.sectionStateChanges.sink { received += 1 }
        appState.menuBarManager.section(withName: .hidden)?.controlItem.state = .showSection
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while received == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(received > 0)
        cancellable.cancel()
    }

    @Test("Setting up without the switch on shows nothing")
    func setupWithSwitchOff() {
        let appState = AppState()
        appState.settings.advanced.enableSwapBar = false
        let manager = SwapBarManager()
        manager.performSetup(with: appState, displaySettlements: PassthroughSubject<EnvironmentChange, Never>())
        #expect(!NSApp.windows.contains { $0 is SwapBarPanel && $0.isVisible })
    }
}
