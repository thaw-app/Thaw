//
//  ThawBarItemViewsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// A Thaw Bar item's click surface and glyph, driven with synthetic events and never clicking a real item.
@MainActor
@Suite("Thaw Bar item views", .serialized)
struct ThawBarItemViewsTests {
    private typealias World = LayoutEditorWorld

    /// Counts what the click surface reports.
    @MainActor
    private final class Calls {
        var left = 0
        var right = 0
        var hovers = [Bool]()
        var menuRequests = 0
    }

    private func clickView(_ calls: Calls, item: MenuBarItem = World.item("Alpha")) -> (ThawBarItemClickView.Represented, NSWindow) {
        let view = ThawBarItemClickView.Represented(
            item: item,
            tooltipDelay: 60,
            leftClickAction: { calls.left += 1 },
            rightClickAction: { calls.right += 1 },
            onHover: { calls.hovers.append($0) }
        )
        view.thawMenuProvider = {
            calls.menuRequests += 1
            return nil
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        return (view, window)
    }

    private func mouse(_ type: NSEvent.EventType, in window: NSWindow, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func entered(in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        ))
    }

    @Test("A quick press and release clicks with the matching button")
    func quickPressClicks() throws {
        let calls = Calls()
        let (view, window) = clickView(calls)
        try view.mouseDown(with: mouse(.leftMouseDown, in: window))
        try view.mouseUp(with: mouse(.leftMouseUp, in: window))
        #expect(calls.left == 1)
        #expect(calls.right == 0)

        try view.rightMouseDown(with: mouse(.rightMouseDown, in: window))
        try view.rightMouseUp(with: mouse(.rightMouseUp, in: window))
        #expect(calls.right == 1)
        #expect(calls.menuRequests == 0, "a plain right click goes to the app's own menu")
    }

    @Test("A release with no press before it is not a click")
    func releaseWithoutPress() throws {
        let calls = Calls()
        let (view, window) = clickView(calls)
        try view.mouseUp(with: mouse(.leftMouseUp, in: window))
        try view.rightMouseUp(with: mouse(.rightMouseUp, in: window))
        #expect(calls.left == 0)
        #expect(calls.right == 0)
    }

    @Test("Option right click asks for Thaw's menu, and falls back to the app's when there is none")
    func optionRightClickAsksForThawsMenu() throws {
        let calls = Calls()
        let (view, window) = clickView(calls)
        try view.rightMouseDown(with: mouse(.rightMouseDown, in: window, flags: .option))
        #expect(calls.menuRequests == 1)
        try view.rightMouseUp(with: mouse(.rightMouseUp, in: window))
        #expect(calls.right == 1)
    }

    @Test("Hovering reports entering and leaving, and tracking follows the bounds")
    func hoverIsReported() throws {
        let calls = Calls()
        let (view, window) = clickView(calls)
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        #expect(view.trackingAreas.count == 1, "the old tracking area is replaced, not stacked")
        #expect(view.trackingAreas.first?.rect == view.bounds)
        let event = try entered(in: window)
        view.mouseEntered(with: event)
        view.mouseExited(with: event)
        #expect(calls.hovers == [true, false])
    }

    @Test("An update swaps the handlers the next click uses")
    func updateSwapsHandlers() throws {
        let calls = Calls()
        let replacement = Calls()
        let (view, window) = clickView(calls)
        view.update(
            item: World.item("Beta"),
            tooltipDelay: 30,
            leftClickAction: { replacement.left += 1 },
            rightClickAction: { replacement.right += 1 },
            onHover: { replacement.hovers.append($0) }
        )
        try view.mouseDown(with: mouse(.leftMouseDown, in: window))
        try view.mouseUp(with: mouse(.leftMouseUp, in: window))
        #expect(calls.left == 0)
        #expect(replacement.left == 1)
        #expect(view.tooltipDelay == 30)
        #expect(view.item.title == "Beta")
    }

    @Test("The glyph view draws an item with an image and nothing without one")
    func glyphDraws() throws {
        let world = World()
        let alpha = World.item("Alpha")
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        func view(_ displayImage: MenuBarItemDisplayImage?, focused: Bool) -> some View {
            ThawBarItemView(
                itemManager: world.appState.itemManager,
                menuBarManager: world.appState.menuBarManager,
                item: alpha,
                section: .hidden,
                displayID: CGMainDisplayID(),
                maxHeight: 22,
                tooltipDelay: 60,
                displayImage: displayImage,
                isKeyboardFocused: focused
            )
            .frame(width: 40, height: 30)
        }
        let size = CGSize(width: 40, height: 30)
        let drawn = try OffscreenRender(view(.appIcon(image), focused: false), size: size).pixels()
        let focused = try OffscreenRender(view(.appIcon(image), focused: true), size: size).pixels()
        let empty = try OffscreenRender(view(nil, focused: false), size: size).pixels()
        #expect(drawn.contains { $0 != 0 })
        #expect(!empty.contains { $0 != 0 })
        // With Reduce Motion on, the highlight is only the glass wash, which an offscreen capture doesn't record.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(focused != drawn, "the keyboard highlight lifts the glyph")
        }
    }
}
