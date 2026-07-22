//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import MenuBarModel

nonisolated enum AXHelpers {
    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        checkIsProcessTrusted(prompt: prompt)
    }

    /// Bounds the systemwide hit-test's AX round trip the same way
    /// `application(for:)` bounds per-app round trips. Without this, hitting a
    /// hung third-party menu-bar app under the cursor blocks
    /// `elementAtPosition` — and therefore the caller's thread — indefinitely,
    /// which for `element(at:)`'s callers is Thaw's main thread during click
    /// handling.
    private static let systemWideMessagingTimeoutSet: Void = {
        try? systemWideElement.setMessagingTimeout(0.25)
    }()

    static func element(at point: CGPoint) -> UIElement? {
        systemWideMessagingTimeoutSet
        return try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y))
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        let app = Application(runningApp)
        // Bound every AX round trip to this app. Without a timeout,
        // AXUIElementCopyAttributeValue blocks on mach_msg until the target
        // app's accessibility server replies — an unresponsive app would
        // otherwise stall menu bar enumeration indefinitely.
        if let app {
            try? app.setMessagingTimeout(0.25)
        }
        return app
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        try? app.attribute(.extrasMenuBar)
    }

    /// The application's normal menu bar (Apple menu + app menus).
    /// Unlike point hit-testing, this remains reliable when Thaw's overlay panel
    /// occupies the screen's menu-bar origin on macOS 27.
    static func menuBar(for app: Application) -> UIElement? {
        try? app.attribute(.menuBar)
    }

    static func children(for element: UIElement) -> [UIElement] {
        (try? element.arrayAttribute(.children)) ?? []
    }

    static func childrenIfAvailable(for element: UIElement) -> [UIElement]? {
        try? element.arrayAttribute(.children)
    }

    /// The element referenced by `AXOverflowButton`, when exposed. Containers
    /// such as the macOS 27 extras menu bar publish their overflow control as
    /// an attribute rather than as an ordinary child.
    static func overflowButton(for element: UIElement) -> UIElement? {
        try? element.attribute(.overflowButton)
    }

    /// Whether the element advertises `AXOverflowButton`, or `nil` when its
    /// attribute list could not be read.
    static func supportsOverflowButton(_ element: UIElement) -> Bool? {
        try? element.attributes().contains(.overflowButton)
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        (try? element.attribute(.enabled)) ?? false
    }

    /// The raw AXEnabled attribute, or nil when the element does not expose it.
    /// isEnabled collapses a missing attribute to false, so it cannot tell an
    /// explicitly disabled element from one that simply does not publish the
    /// attribute. Callers that must keep that distinction use this: source-PID
    /// matching treats absent as enabled, and the unresolved-item diagnostics
    /// report it verbatim.
    static func enabledAttribute(_ element: UIElement) -> Bool? {
        try? element.attribute(.enabled)
    }

    static func frame(for element: UIElement) -> CGRect? {
        try? element.attribute(.frame)
    }

    static func role(for element: UIElement) -> Role? {
        try? element.role()
    }

    /// Raw `AXRole` string. Prefer this when AXSwift6's `Role` enum is missing a
    /// case (notably `AXMenuBarItem`).
    static func roleString(for element: UIElement) -> String? {
        try? element.attribute(.role) as String?
    }

    /// Whether the element is menu-bar chrome (menu bar, menu, or menu item).
    /// Used to distinguish the front app's menu titles from third-party overlays.
    static func isMenuBarChromeRole(_ element: UIElement) -> Bool {
        switch roleString(for: element) {
        case "AXMenuBar", "AXMenu", "AXMenuItem", "AXMenuBarItem":
            true
        default:
            false
        }
    }

    /// Unions the frames of application menu titles in a menu bar element.
    ///
    /// On macOS 27 the menu bar's AX children can include status-item hosts;
    /// unioning every child made the split leading pill swallow the status
    /// area. Keep only menu-bar item roles there.
    static func applicationMenuChildFrameUnion(for menuBar: UIElement) -> CGRect {
        children(for: menuBar).reduce(into: CGRect.null) { result, child in
            guard isEnabled(child), let childFrame = frame(for: child) else {
                return
            }
            if #available(macOS 27, *) {
                switch roleString(for: child) {
                case "AXMenuBarItem", "AXMenuItem":
                    result = result.union(childFrame)
                default:
                    break
                }
            } else {
                result = result.union(childFrame)
            }
        }
    }

    /// The element's `AXTitle`, when present. On macOS 27 most menu bar
    /// item elements leave this empty, so callers fall back to ``identifier``.
    static func title(for element: UIElement) -> String? {
        try? element.attribute(.title)
    }

    /// The element's `AXIdentifier`, when present. Thaw sets a stable
    /// identifier on its control-item buttons so they can be recognized in
    /// the macOS 27 Accessibility-based enumeration.
    static func identifier(for element: UIElement) -> String? {
        try? element.attribute(.identifier)
    }

    /// The element's accessibility description. Some status-item apps expose
    /// a stable semantic label here while `AXTitle` contains live metric text.
    static func description(for element: UIElement) -> String? {
        try? element.attribute(.description)
    }

    static func pid(for element: UIElement) -> pid_t? {
        try? element.pid()
    }

    /// Performs the press action on the given element, returning whether it
    /// succeeded. Used to open the menus of Electron/Chromium tray items, which
    /// ignore synthetic mouse clicks.
    @discardableResult
    static func press(_ element: UIElement) -> Bool {
        do {
            try element.performAction(.press)
            return true
        } catch {
            return false
        }
    }
}
