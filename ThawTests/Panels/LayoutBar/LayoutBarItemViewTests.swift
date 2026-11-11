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

        /// offset moves the event along x, so a drag can pass the tile's 3 pt threshold.
        func mouse(_ type: NSEvent.EventType, on view: NSView, offset: CGFloat = 0) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: view.convert(NSPoint(x: view.bounds.midX + offset, y: view.bounds.midY), to: nil),
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

    @Test("A tile with no picture shows its app's icon, and the generic glyph only when the app can't be found")
    func placeholderUsesTheAppIcon() throws {
        let appState = World().appState
        func item(sourcePID: pid_t?) -> MenuBarItem {
            MenuBarItem(
                tag: MenuBarItemTag(namespace: .string("com.example.placeholder"), title: "Item-0", windowID: 7),
                windowID: 7, ownerPID: getpid(), sourcePID: sourcePID,
                bounds: CGRect(x: 0, y: 0, width: 24, height: 24), title: "Item-0", isOnScreen: false
            )
        }
        // A running app hidden by Native hiding is never drawn, so it never has a picture.
        let appIcon = try #require(LayoutBarItemView.makePlaceholderImage(for: item(sourcePID: getpid()), appState: appState))
        #expect(!appIcon.isTemplate, "the app's own icon, not a symbol")
        let glyph = try #require(LayoutBarItemView.makePlaceholderImage(for: item(sourcePID: nil), appState: appState))
        #expect(glyph.isTemplate, "the generic menu bar glyph")
    }

    /// 2026-11-06: Bluetooth, hidden by switching its module off, showed its symbol inside the grey box.
    @Test("A switched-off system module draws its symbol without the box; other tiles keep it")
    func moduleGlyphDrawsBare() throws {
        func item(_ namespace: MenuBarItemTag.Namespace, _ title: String) -> MenuBarItem {
            MenuBarItem(
                tag: MenuBarItemTag(namespace: namespace, title: title, windowID: 9),
                windowID: 9, ownerPID: 0, sourcePID: nil,
                bounds: CGRect(x: 0, y: 0, width: 24, height: 24), title: nil, isOnScreen: false
            )
        }
        #expect(LayoutBarItemView.drawsBareModuleGlyph(for: item(.menuBarAgent, "com.apple.menuextra.bluetooth")))
        #expect(!LayoutBarItemView.drawsBareModuleGlyph(for: item(.menuBarAgent, "com.example.unknown")))
        #expect(!LayoutBarItemView.drawsBareModuleGlyph(for: item(.string("com.example.app"), "com.apple.menuextra.bluetooth")))

        #expect(LayoutBarItemView.bareGlyphFraction(isEnabled: true) == 1)
        #expect(LayoutBarItemView.bareGlyphFraction(isEnabled: false) == 0.67, "dimmed like a disabled picture")

        let tile = CGRect(x: 0, y: 0, width: 40, height: 24)
        let rect = try #require(LayoutBarItemView.bareGlyphRect(for: CGSize(width: 16, height: 16), in: tile))
        #expect(rect.width == rect.height)
        #expect(rect.midX == 20 && rect.midY == 12)
        #expect(rect.height == 24, "a square symbol fills the square")

        // Wi-Fi's symbol is 18 by 13. Filling the square squeezed it.
        let wide = try #require(LayoutBarItemView.bareGlyphRect(for: CGSize(width: 18, height: 13), in: tile))
        #expect(wide.width == 24)
        #expect(abs(wide.width / wide.height - 18.0 / 13.0) < 0.0001, "the symbol keeps its proportions")
        #expect(wide.midX == 20 && wide.midY == 12)
        #expect(wide == LayoutBarItemView.overflowFallbackDrawRect(
            for: item(.menuBarAgent, "com.apple.menuextra.wifi"), imageSize: CGSize(width: 18, height: 13), bounds: tile
        ))
        let tall = try #require(LayoutBarItemView.bareGlyphRect(for: CGSize(width: 10, height: 20), in: tile))
        #expect(tall.height == 24 && tall.width == 12)
        #expect(LayoutBarItemView.bareGlyphRect(for: .zero, in: tile)?.size == CGSize(width: 24, height: 24), "no size to go by")
        #expect(rect == LayoutBarItemView.overflowFallbackDrawRect(
            for: item(.menuBarAgent, "com.apple.menuextra.bluetooth"), imageSize: CGSize(width: 16, height: 16),
            bounds: CGRect(x: 0, y: 0, width: 40, height: 24)
        ))
        #expect(LayoutBarItemView.bareGlyphRect(for: CGSize(width: 16, height: 16), in: .zero) == nil)

        let bluetooth = item(.menuBarAgent, "com.apple.menuextra.bluetooth")
        let bar = try Bar([bluetooth])
        let view = try bar.view(bluetooth)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let corner = try #require(bitmap.colorAt(x: 3, y: 3))
        #expect(corner.alphaComponent == 0, "no box behind the symbol")
        let glyphRect = try #require(LayoutBarItemView.bareGlyphRect(for: CGSize(width: 16, height: 16), in: view.bounds))
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let inked = (Int(glyphRect.minX * scale) ..< Int(glyphRect.maxX * scale)).contains { x in
            (Int(glyphRect.minY * scale) ..< Int(glyphRect.maxY * scale)).contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            }
        }
        #expect(inked, "the symbol itself is drawn")
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
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view, offset: 4))
        let first = try #require(bar.world.appState.layoutFeedback.refusal)
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view, offset: 5))
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
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view, offset: 4))
        let refusal = try #require(bar.world.appState.layoutFeedback.refusal)
        #expect(refusal.message == LayoutBarFeedbackCenter.ownerUnresponsive(itemName: alpha.displayName).message)
    }

    @Test("A wobble under three points stays a click and raises no refusal")
    func wobbleStaysAClick() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        view.isEnabled = false
        try view.mouseDown(with: bar.mouse(.leftMouseDown, on: view))
        try view.mouseDragged(with: bar.mouse(.leftMouseDragged, on: view, offset: 2))
        #expect(bar.world.appState.layoutFeedback.refusal == nil)
        #expect(view.pointer.isClickCandidate)
    }

    @Test("Hovering a tile draws the accent wash, and leaving clears it")
    func hoverDrawsWash() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        let plain = try pixels(of: view)
        let entered = try #require(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: bar.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        view.mouseEntered(with: entered)
        #expect(try pixels(of: view) != plain)
        let exited = try #require(NSEvent.enterExitEvent(
            with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: bar.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        view.mouseExited(with: exited)
        #expect(try pixels(of: view) == plain)
    }

    @Test("The unresponsive badge explains itself in the tooltip and to VoiceOver")
    func unresponsiveBadgeHelp() throws {
        let alpha = World.item("Alpha")
        let bar = try Bar([alpha])
        let view = try bar.view(alpha)
        view.isOwnerUnresponsive = true
        #expect(view.toolTip?.contains("isn’t responding") == true)
        #expect(view.accessibilityHelp() == view.toolTip)
        view.isOwnerUnresponsive = false
        #expect(view.toolTip == nil)
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
