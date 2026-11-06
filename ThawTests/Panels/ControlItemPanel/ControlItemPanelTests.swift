//
//  ControlItemPanelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
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

    /// A visible control item whose window ID the window server has never issued, so the bounds lookup fails.
    private static func controlItem(bounds: CGRect) -> MenuBarItem {
        MenuBarItem(
            tag: .visibleControlItem,
            windowID: CGWindowID(UInt32.max - 7),
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            sourcePID: ProcessInfo.processInfo.processIdentifier,
            bounds: bounds,
            title: MenuBarItemTag.visibleControlItem.title,
            isOnScreen: true
        )
    }

    @Test("The popover is transient, reports back to the controller and sizes itself from its contents")
    func popoverConfiguration() throws {
        let appState = AppState()
        let controller = ControlItemPanelController()
        let popover = controller.makePopover(appState: appState)
        #expect(popover.behavior == .transient)
        #expect(popover.animates)
        #expect(popover.delegate === controller)
        let hosting = try #require(popover.contentViewController as? NSHostingController<ControlItemPanelView>)
        #expect(hosting.sizingOptions == [.preferredContentSize])
        #expect(!controller.isShown, "building the popover does not show it")
    }

    @Test("Without Thaw's icon in the item list there are no icon bounds to anchor to")
    func noControlItemNoBounds() {
        let appState = AppState()
        let controller = ControlItemPanelController()
        controller.performSetup(with: appState)
        appState.itemManager.itemCache[.visible] = [LayoutEditorWorld.item("Alpha")]
        #expect(controller.anchorBounds() == nil)
    }

    @Test("When the window server cannot place the icon, its cached bounds stand in, also on the next lookup")
    func cachedBoundsFallback() {
        let appState = AppState()
        let controller = ControlItemPanelController()
        controller.performSetup(with: appState)
        let bounds = CGRect(x: 700, y: 0, width: 30, height: 24)
        appState.itemManager.itemCache[.visible] = [Self.controlItem(bounds: bounds)]
        #expect(controller.anchorBounds() == bounds)
        #expect(controller.anchorBounds() == bounds, "the failed lookup is remembered, not repeated")
    }

    @Test("An icon with no cached bounds gives no anchor bounds", arguments: [false, true])
    func emptyBoundsGiveNothing(lookedUpBefore: Bool) {
        let appState = AppState()
        let controller = ControlItemPanelController()
        controller.performSetup(with: appState)
        if lookedUpBefore {
            appState.itemManager.itemCache[.visible] = [Self.controlItem(bounds: CGRect(x: 1, y: 0, width: 1, height: 1))]
            _ = controller.anchorBounds()
        }
        appState.itemManager.itemCache[.visible] = [Self.controlItem(bounds: .zero)]
        #expect(controller.anchorBounds() == nil)
    }

    @Test("The fallback anchor hangs under the menu bar at the icon's x, or the click's x without an icon")
    func fallbackAnchorFrame() throws {
        let screen = try #require(NSScreen.main)
        let appState = AppState()
        let controller = ControlItemPanelController()
        controller.performSetup(with: appState)
        let point = CGPoint(x: screen.frame.minX + 40, y: screen.frame.maxY - 5)
        let underBar = screen.frame.maxY - screen.getMenuBarHeightEstimate()

        let atClick = try #require(controller.anchorFrame(fallbackPoint: point))
        #expect(atClick == CGRect(x: point.x, y: underBar, width: 1, height: 1))

        let bounds = CGRect(x: 700, y: 0, width: 30, height: 24)
        appState.itemManager.itemCache[.visible] = [Self.controlItem(bounds: bounds)]
        let atIcon = try #require(controller.anchorFrame(fallbackPoint: point))
        #expect(atIcon.origin == CGPoint(x: bounds.midX, y: underBar))
    }

    @Test("With neither an icon nor a click the anchor sits at the middle of a screen")
    func anchorWithoutAPoint() throws {
        let controller = ControlItemPanelController()
        let frame = try #require(controller.anchorFrame(fallbackPoint: nil))
        let screen = try #require(NSScreen.screenWithMouse ?? NSScreen.main)
        #expect(frame == CGRect(x: screen.frame.midX, y: screen.frame.maxY - screen.getMenuBarHeightEstimate(), width: 1, height: 1))
    }
}
