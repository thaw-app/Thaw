//
//  ControlItemPanelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The control item popover's controller and contents, built off screen with throwaway settings.
@Suite("Control item panel", .serialized, .scratchDefaults)
@MainActor
struct ControlItemPanelTests {
    @Test("Before setup the experiment reads as off and nothing is shown")
    func beforeSetup() {
        let controller = ControlItemPanelController()
        #expect(!controller.isEnabled)
        #expect(!controller.isShown)
        controller.toggle(anchor: nil, fallbackPoint: nil)
        #expect(!controller.isShown, "without an app state there is nothing to show")
        controller.hide()
        #expect(!controller.isShown)
    }

    @Test("The experiment flag is read live from settings")
    func enabledFollowsSetting() {
        let appState = AppState()
        let controller = ControlItemPanelController()
        controller.performSetup(with: appState)
        appState.settings.advanced.enableControlItemPanel = false
        #expect(!controller.isEnabled)
        appState.settings.advanced.enableControlItemPanel = true
        #expect(controller.isEnabled)
    }

    @Test("A close notice from a popover the controller does not own is ignored")
    func foreignPopoverClose() {
        let controller = ControlItemPanelController()
        controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))
        #expect(!controller.isShown)
    }

    @Test("The contents draw at the panel's fixed width")
    func contentsDraw() throws {
        let appState = AppState()
        var dismissals = 0
        let view = ControlItemPanelView(appState: appState) { dismissals += 1 }
        let size = NSHostingView(rootView: view).fittingSize
        #expect(size.width == 260)
        #expect(size.height > 200, "every row is laid out")
        let render = OffscreenRender(view, size: size)
        #expect(try render.pixels().contains { $0 != 0 })
        #expect(dismissals == 0, "drawing never dismisses")
    }

    @Test("A section state change reaches the view's stored publisher")
    func sectionChangesPublisher() async {
        let appState = AppState()
        let view = ControlItemPanelView(appState: appState) { /* Never dismissed here. */ }
        var received = 0
        let cancellable = view.sectionStateChanges.sink { received += 1 }
        appState.menuBarManager.section(withName: .alwaysHidden)?.controlItem.state = .showSection
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while received == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(received > 0)
        cancellable.cancel()
    }
}
