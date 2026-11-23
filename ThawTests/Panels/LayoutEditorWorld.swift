//
//  LayoutEditorWorld.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// An app state whose item cache holds items owned by the test process, so they count as running.
@MainActor
struct LayoutEditorWorld {
    let appState = AppState()
    private static var nextWindowID: CGWindowID = 9000

    static func item(_ tag: MenuBarItemTag, ownerPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> MenuBarItem {
        nextWindowID += 1
        return MenuBarItem(
            tag: tag,
            windowID: nextWindowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: CGRect(x: CGFloat(nextWindowID), y: 0, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    static func item(_ title: String) -> MenuBarItem {
        item(MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0))
    }

    func seat(_ items: [MenuBarItem], in section: MenuBarSection.Name = .visible) {
        appState.itemManager.itemCache[section] = items
    }
}

/// A drag that a Layout drop view can read: a source, a location and a pasteboard, and nothing to animate.
@MainActor
final class TestDrag: NSObject, NSDraggingInfo {
    let draggingSource: Any?
    var draggingLocation: NSPoint
    let draggingPasteboard: NSPasteboard
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(
        source: Any? = nil,
        location: NSPoint = .zero,
        pasteboard: NSPasteboard = NSPasteboard(name: NSPasteboard.Name("ThawTests.TestDrag"))
    ) {
        draggingSource = source
        draggingLocation = location
        draggingPasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? {
        nil
    }

    var draggingSourceOperationMask: NSDragOperation {
        .move
    }

    var draggedImageLocation: NSPoint {
        draggingLocation
    }

    var draggedImage: NSImage? {
        nil
    }

    var draggingSequenceNumber: Int {
        1
    }

    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) { /* Drop views never slide the image. */ }

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) { /* Drop views read the pasteboard, not the dragging items. */ }

    func resetSpringLoading() { /* Not spring-loaded. */ }
}

extension NSView {
    /// The view's pixels as it draws its bounds now.
    func cachedPixels() throws -> Data {
        let bitmap = try #require(bitmapImageRepForCachingDisplay(in: bounds))
        cacheDisplay(in: bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}
