//
//  LayoutBarItemViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// A layout bar tile's drawing, badges, tooltips and refused drags. No test hovers a tile, opens its
/// inspector or starts a drag, since those reach the live menu bar.
@MainActor
@Suite("Layout bar item view", .serialized, .scratchDefaults)
struct LayoutBarItemViewTests {
    private typealias World = LayoutEditorWorld

    /// One Visible bar in an offscreen window.
    @MainActor
    private final class Bar {
        let world = World()
        let window: NSWindow
        let scrollView: LayoutBarScrollView

        init(_ items: [MenuBarItem]) throws {
            world.seat(items, in: .visible)
            scrollView = LayoutBarScrollView(appState: world.appState, section: .visible)
            let frame = CGRect(x: 0, y: 0, width: 600, height: 48)
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scrollView
            scrollView.translatesAutoresizingMaskIntoConstraints = true
            scrollView.frame = frame
            let container = try #require(scrollView.documentView?.subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first)
            container.rebuildViews()
            window.layoutIfNeeded()
        }

        func view(_ item: MenuBarItem) throws -> LayoutBarItemView {
            try #require(scrollView.arrangedViews.lazy.compactMap { $0 as? LayoutBarItemView }.first { $0.item.tag == item.tag })
        }

        func mouse(_ type: NSEvent.EventType, on view: NSView) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }
    }

    private func pixels(of view: NSView) throws -> Data {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @Test("A fallback icon fills the tile's square, and Thaw's own icon keeps its size")
    func fallbackDrawRect() {
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
        let square = LayoutBarItemView.overflowFallbackDrawRect(for: World.item("Alpha"), imageSize: CGSize(width: 64, height: 64), bounds: bounds)
        #expect(square == CGRect(x: 10, y: 0, width: 20, height: 20))

        let icon = World.item(.visibleControlItem)
        let small = LayoutBarItemView.overflowFallbackDrawRect(for: icon, imageSize: CGSize(width: 10, height: 8), bounds: bounds)
        #expect(small.size == CGSize(width: 10, height: 8), "a small control icon is not enlarged")
        #expect(small.midX == bounds.midX)
        let large = LayoutBarItemView.overflowFallbackDrawRect(for: icon, imageSize: CGSize(width: 80, height: 40), bounds: bounds)
        #expect(large.size == CGSize(width: 40, height: 20), "a large one is scaled down to fit")
        #expect(LayoutBarItemView.overflowFallbackDrawRect(for: icon, imageSize: CGSize(width: 10, height: 10), bounds: .zero) == .zero)
    }

    @Test("Padding is added only for a captured system preview")
    func systemPadding() {
        #expect(LayoutBarItemView.systemItemHorizontalPadding(for: World.item("Alpha"), image: nil, desiredPadding: 16) == 0)
    }

    @Test("A rendered tile has the tile's size, with or without a capture")
    func renderedTile() {
        let world = World()
        let alpha = World.item("Alpha")
        let tile = LayoutBarItemView.renderedTile(for: alpha, in: .visible, appState: world.appState)
        #expect(tile.size.width >= 14)
        #expect(tile.size.height >= 18)
        #expect(!tile.representations.isEmpty)
        let icon = LayoutBarItemView.renderedTile(for: World.item(.visibleControlItem), in: .visible, appState: world.appState)
        #expect(!icon.representations.isEmpty)
    }

    @Test("The foreground ink is black or white")
    func foregroundInk() {
        let world = World()
        let ink = LayoutBarItemView.menuBarForegroundColor(appState: world.appState)
        #expect(ink == .black || ink == .white)
    }

    @Test("Disabled, unresponsive and limited tiles draw differently, and a dragged one draws nothing")
    func tileStates() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        let normal = try pixels(of: view)
        #expect(normal.contains { $0 != 0 })

        view.isEnabled = false
        let disabled = try pixels(of: view)
        view.isEnabled = true
        view.isOwnerUnresponsive = true
        let unresponsive = try pixels(of: view)
        view.isOwnerUnresponsive = false
        view.visibilityLimit = .cannotHide
        #expect(view.toolTip == LayoutBarVisibilityLimit.cannotHide.explanation)
        let limited = try pixels(of: view)
        view.visibilityLimit = nil
        #expect(view.toolTip == nil)

        #expect(Set([normal, disabled, unresponsive, limited]).count == 4)
        view.isDraggingPlaceholder = true
        #expect(try !pixels(of: view).contains { $0 != 0 })
        view.isDraggingPlaceholder = false
        #expect(view.draggingImage() != nil)
    }

    @Test("Thaw's own icon tile draws its icon")
    func thawIconTile() throws {
        let icon = World.item(.visibleControlItem)
        let bar = try Bar([World.item("Alpha"), icon])
        let view = try bar.view(icon)
        #expect(try pixels(of: view).contains { $0 != 0 })
        #expect(view.draggingImage() != nil)
    }

    @Test("Dragging a tile macOS will not move explains once and never becomes a click")
    func refusedDragExplainsOnce() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        view.isEnabled = false

        try view.mouseDown(with: bar.mouse(.leftMouseDown, on: view))
        #expect(bar.window.firstResponder === view, "a press focuses the tile")
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view))
        let first = try #require(bar.world.appState.layoutFeedback.refusal)
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view))
        #expect(bar.world.appState.layoutFeedback.refusal == first, "the refusal is posted once per press")
        try view.mouseUp(with: bar.mouse(.leftMouseUp, on: view))
        #expect(bar.world.appState.navigationState.isLayoutEditorPresented == false)
    }

    @Test("Dragging a tile whose app is not responding says so")
    func unresponsiveDragExplains() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        try #require(view.isEnabled)
        view.isOwnerUnresponsive = true
        try view.mouseDown(with: bar.mouse(.leftMouseDown, on: view))
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view))
        let refusal = try #require(bar.world.appState.layoutFeedback.refusal)
        #expect(refusal.message == LayoutBarFeedbackCenter.ownerUnresponsive(itemName: alpha.displayName).message)
    }

    @Test("A tile adopts a refreshed item, and names where macOS puts it because of its app")
    func adoptAndOverride() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        let refreshed = World.item(alpha.tag)
        view.adopt(item: refreshed, appState: bar.world.appState)
        #expect(view.item.windowID == refreshed.windowID)
        #expect(view.accessibilityLabel() == refreshed.displayName)

        view.appWideOverride = .hiddenWithApp(.hidden)
        #expect(view.accessibilityHelp() == AppWideOverride.hiddenWithApp(.hidden).tooltip(itemName: refreshed.displayName))
        view.appWideOverride = nil
        #expect(view.accessibilityHelp() == nil)
    }

    @Test("A tile joins the key view loop, redraws on focus and lets go of a closed inspector")
    func focusAndPopover() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        #expect(bar.window.makeFirstResponder(view))
        #expect(view.needsDisplay)
        #expect(bar.window.makeFirstResponder(nil))
        view.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        #expect(view.trackingAreas.count == 1)
        try view.mouseUp(with: bar.mouse(.leftMouseUp, on: view))
        #expect(!view.isLayoutSelected)
    }
}
