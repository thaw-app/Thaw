//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa

nonisolated enum AXHelpers {
    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        checkIsProcessTrusted(prompt: prompt)
    }

    static func element(at point: CGPoint) -> UIElement? {
        try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y))
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        Application(runningApp)
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        try? app.attribute(.extrasMenuBar)
    }

    static func children(for element: UIElement) -> [UIElement] {
        (try? element.arrayAttribute(.children)) ?? []
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

    /// The element's `AXIdentifier` attribute (e.g. `com.apple.menuextra.wifi`
    /// for a Control Center-hosted module), when the element publishes one.
    static func identifier(for element: UIElement) -> String? {
        try? element.attribute(.identifier)
    }

    /// The element's `AXHelp` attribute (tooltip/description string).
    static func help(for element: UIElement) -> String? {
        try? element.attribute(.help)
    }

    /// The element's `AXTitle` attribute.
    static func title(for element: UIElement) -> String? {
        try? element.attribute(.title)
    }

    static func role(for element: UIElement) -> Role? {
        try? element.role()
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
