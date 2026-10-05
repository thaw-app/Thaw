//
//  AXPrimitives.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Shared raw AX operations keep app and helper walks consistent using only system frameworks.
/// The helper calls directly; AXHelpers bridges the app's AXSwift6 wrappers through action and owner closures.
public enum AXPrimitives {
    /// Bound AX round trips below the system's roughly six-second timeout so one hung app cannot stall reads or presses.
    public static let defaultMessagingTimeout: Float = 0.25

    // MARK: - Open menus

    /// The window layer the window server puts open menus on.
    private static let popupMenuWindowLayer = 101

    /// Whether the process has an open menu on screen, which distinguishes an
    /// owner busy tracking the menu it just opened from one that is hung.
    public static func isTrackingOpenMenu(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            window[kCGWindowLayer as String] as? Int == popupMenuWindowLayer &&
                window[kCGWindowOwnerPID as String] as? pid_t == pid
        }
    }

    // MARK: - Presses

    /// In-process NSMenu tracking can return cannotComplete after a successful press; out-of-process menus return success.
    /// Confirm the owner's menu through WindowServer to avoid retrying and closing it or clicking over it.
    @discardableResult
    public static func press(
        _ element: AXUIElement,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> Bool {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return press(
            perform: { AXUIElementPerformAction(element, kAXPressAction as CFString) },
            ownerPID: { pid(of: element) }
        )
    }

    /// Closures bridge AXSwift6 wrappers that do not expose raw elements, sharing cannotComplete resolution.
    /// Query ownerPID only on cannotComplete to avoid an extra round trip on the common path.
    @discardableResult
    public static func press(
        perform: () -> AXError,
        ownerPID: () -> pid_t?
    ) -> Bool {
        switch perform() {
        case .success:
            return true
        case .cannotComplete:
            guard let pid = ownerPID() else { return false }
            return isTrackingOpenMenu(pid: pid)
        default:
            return false
        }
    }

    // MARK: - Frames

    /// Use the midpoint to attribute boundary-straddling frames to the display they mostly occupy.
    public static func frame(_ frame: CGRect, isWithin displayBounds: CGRect) -> Bool {
        // WindowServer parks unlaid-out items at x == -1; retain them in inventory for rescue despite no display match.
        if frame.origin.x == -1 {
            return true
        }
        return frame.midY >= displayBounds.minY &&
            frame.midY <= displayBounds.maxY &&
            frame.midX >= displayBounds.minX &&
            frame.midX <= displayBounds.maxX
    }

    /// The frame to inventory as a status item, or nil for a popover or panel.
    ///
    /// Some items report a box far taller than the bar, centred on it. Popovers hang below the
    /// bar; a box that also reaches above its display's top edge is a mis-sized item, so it is
    /// cut to the bar band its centre implies.
    public static func itemFrame(_ frame: CGRect, maximumHeight: CGFloat, displayTop: CGFloat?) -> CGRect? {
        guard frame.height > 0 else { return nil }
        if frame.height <= maximumHeight {
            return frame
        }
        guard let displayTop, frame.minY < displayTop else { return nil }
        let barHeight = 2 * (frame.midY - displayTop)
        guard barHeight > 0, barHeight <= maximumHeight else { return nil }
        return CGRect(x: frame.minX, y: displayTop, width: frame.width, height: barHeight)
    }

    /// itemFrame(_:maximumHeight:displayTop:) against the display under the frame's centre,
    /// looked up only for a frame over the ceiling.
    public static func itemFrame(_ frame: CGRect, maximumHeight: CGFloat) -> CGRect? {
        guard frame.height > maximumHeight else {
            return itemFrame(frame, maximumHeight: maximumHeight, displayTop: nil)
        }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let top = CGGetDisplaysWithPoint(center, 1, &display, &count) == .success && count == 1
            ? CGDisplayBounds(display).minY
            : nil
        return itemFrame(frame, maximumHeight: maximumHeight, displayTop: top)
    }

    /// The element's frame, preferring AXFrame and falling back to
    /// AXPosition plus AXSize for elements that do not vend it.
    public static func frame(of element: AXUIElement) -> CGRect? {
        if let value = copyAttribute(element, "AXFrame"),
           CFGetTypeID(value) == AXValueGetTypeID()
        {
            var rect = CGRect.zero
            if AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) {
                return rect
            }
        }
        guard let positionValue = copyAttribute(element, kAXPositionAttribute),
              let sizeValue = copyAttribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Attribute reads

    public static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    public static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    public static func children(of element: AXUIElement) -> [AXUIElement] {
        (copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    public static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copyAttribute(element, attribute) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    public static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    // MARK: - Application menus

    /// Frames of the app's menu bar titles, or nil when the menu bar could
    /// not be read at all.
    public static func applicationMenuFrames(
        pid: pid_t,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> [CGRect]? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let menuBar = elementAttribute(appElement, kAXMenuBarAttribute as String) else {
            return nil
        }
        return children(of: menuBar).compactMap { frame(of: $0) }
    }

    // MARK: - MenuBarAgent

    /// The MenuBarAgent's process, which publishes the system status items.
    public static func menuBarAgentPID() -> pid_t? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.MenuBarAgent"
        ).first?.processIdentifier
    }

    /// The extras menu bar of the MenuBarAgent, or nil when the agent is not
    /// running or its bar cannot be read.
    public static func menuBarAgentExtrasBar(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> AXUIElement? {
        guard let pid = menuBarAgentPID() else { return nil }
        return extrasMenuBar(pid: pid, messagingTimeout: messagingTimeout)
    }

    /// The extras menu bar of one application.
    public static func extrasMenuBar(
        pid: pid_t,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        return elementAttribute(appElement, kAXExtrasMenuBarAttribute as String)
    }

    // MARK: - Status-item presses

    /// Presses one of pid's own status items. With several, only the one
    /// whose frame centre lies within tolerance of target is pressed.
    public static func pressNearestStatusItem(
        pid: pid_t,
        target: CGPoint,
        tolerance: Double,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> Bool {
        guard let bar = extrasMenuBar(pid: pid, messagingTimeout: messagingTimeout) else {
            return false
        }
        let items = children(of: bar)
        // One item is unambiguous; multiple items require a target match to avoid opening the wrong menu.
        if items.count == 1 {
            return press(items[0], messagingTimeout: messagingTimeout)
        }
        let nearest = items
            .compactMap { item in
                frame(of: item).map { (item, hypot($0.midX - target.x, $0.midY - target.y)) }
            }
            .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 <= tolerance else {
            return false
        }
        return press(nearest.0, messagingTimeout: messagingTimeout)
    }

    /// Presses a status item MenuBarAgent hosts on behalf of sourcePID.
    public static func pressHostedItem(
        sourcePID: pid_t,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> Bool {
        guard let bar = menuBarAgentExtrasBar(messagingTimeout: messagingTimeout) else {
            return false
        }
        for child in children(of: bar) where pid(of: child) == sourcePID {
            for element in children(of: child) + [child] where press(element, messagingTimeout: messagingTimeout) {
                return true
            }
        }
        return false
    }

    // MARK: - Hit testing

    /// Hit-tests global screen coordinates with a bounded timeout so a hung app under the pointer cannot stall the caller.
    public static func hitTestElement(
        at point: CGPoint,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &element
        ) == .success else {
            return nil
        }
        return element
    }
}
