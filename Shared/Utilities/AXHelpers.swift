//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import AXSwift6
import Cocoa
import MenuBarModel
import ThawAXCore

nonisolated enum AXHelpers {
    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        checkIsProcessTrusted(prompt: prompt)
    }

    /// Bounds the systemwide hit-test. Without it, a hung app under the cursor
    /// blocks elementAtPosition, and Thaw's main thread with it, indefinitely.
    private static let systemWideMessagingTimeoutSet: Void = {
        try? systemWideElement.setMessagingTimeout(AXPrimitives.defaultMessagingTimeout)
    }()

    /// nil off the main thread when point is over a Thaw window.
    static func element(at point: CGPoint) -> UIElement? {
        guard !WindowInfo.isUnsafeAccessibilityHitTest(at: point) else {
            return nil
        }
        systemWideMessagingTimeoutSet
        return try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y))
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        let app = Application(runningApp)
        // Without a timeout, an unresponsive app stalls enumeration
        // indefinitely in mach_msg.
        if let app {
            try? app.setMessagingTimeout(AXPrimitives.defaultMessagingTimeout)
        }
        return app
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        try? app.attribute(.extrasMenuBar)
    }

    /// Everything the walk reads from one extras-bar child, in one message.
    /// The timeout bounds each read, so batching caps a slow app at one timeout
    /// per item. Unanswered attributes are nil, as in the single accessors.
    struct MenuBarChildAttributes {
        var role: String?
        var frame: CGRect?
        var identifier: String?
        var title: String?
        var accessibilityDescription: String?
        var children: [UIElement] = []
    }

    /// Pass includingRole only for MenuBarAgent's bar. The walks also read Thaw's own bar off the
    /// main thread, where AppKit answers in-process and is not thread-safe, so that read stays minimal.
    static func menuBarChildAttributes(for element: UIElement, includingRole: Bool = false) -> MenuBarChildAttributes {
        let values = element.attributeValues((includingRole ? [.role] : []) + [
            .frame, .identifier, .title, .description, .children,
        ])
        return MenuBarChildAttributes(
            role: values[.role] as? String,
            frame: values[.frame] as? CGRect,
            identifier: values[.identifier] as? String,
            title: values[.title] as? String,
            accessibilityDescription: values[.description] as? String,
            children: values[.children] as? [UIElement] ?? []
        )
    }

    /// The same reading below a status item. Never asks a menu for its
    /// children: that builds the menu, and some apps activate when it happens.
    ///
    /// - Parameter includingChildren: Whether to fetch the children at all,
    ///   for a walk that descends further. Never fetched for a menu.
    static func descendantAttributes(
        for element: UIElement,
        includingChildren: Bool = false
    ) -> MenuBarChildAttributes {
        let values = element.attributeValues([
            .role, .frame, .identifier, .title, .description,
        ])
        let role = values[.role] as? String
        return MenuBarChildAttributes(
            role: role,
            frame: values[.frame] as? CGRect,
            identifier: values[.identifier] as? String,
            title: values[.title] as? String,
            accessibilityDescription: values[.description] as? String,
            children: includingChildren && role != "AXMenu" ? children(for: element) : []
        )
    }

    /// The application's normal menu bar (Apple menu + app menus).
    /// Unlike point hit-testing, this remains reliable when Thaw's overlay panel
    /// occupies the screen's menu-bar origin on macOS 27.
    static func menuBar(for app: Application) -> UIElement? {
        try? app.attribute(.menuBar)
    }

    /// A menu bar's or a status item's children. Below a status item, read
    /// through descendantAttributes(for:includingChildren:) instead.
    static func children(for element: UIElement) -> [UIElement] {
        (try? element.arrayAttribute(.children)) ?? []
    }

    /// The element's AXHelp attribute (tooltip/description string).
    static func help(for element: UIElement) -> String? {
        try? element.attribute(.help)
    }

    static func childrenIfAvailable(for element: UIElement) -> [UIElement]? {
        try? element.arrayAttribute(.children)
    }

    /// The element referenced by AXOverflowButton, when exposed. Containers
    /// such as the macOS 27 extras menu bar publish their overflow control as
    /// an attribute rather than as an ordinary child.
    static func overflowButton(for element: UIElement) -> UIElement? {
        try? element.attribute(.overflowButton)
    }

    /// The children of MenuBarAgent's extras bar that are its overflow
    /// chevron by role. See AXPrimitives.isMenuBarAgentOverflowRole(_:).
    static func overflowButtons(among children: [UIElement]) -> [UIElement] {
        children.filter { AXPrimitives.isMenuBarAgentOverflowRole(roleString(for: $0)) }
    }

    /// Whether the element advertises AXOverflowButton, or nil when its
    /// attribute list could not be read.
    static func supportsOverflowButton(_ element: UIElement) -> Bool? {
        try? element.attributes().contains(.overflowButton)
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        (try? element.attribute(.enabled)) ?? false
    }

    /// The raw AXEnabled attribute, or nil when not exposed. Unlike isEnabled,
    /// this tells "disabled" from "absent"; source-PID matching treats absent as enabled.
    static func enabledAttribute(_ element: UIElement) -> Bool? {
        try? element.attribute(.enabled)
    }

    static func frame(for element: UIElement) -> CGRect? {
        try? element.attribute(.frame)
    }

    static func role(for element: UIElement) -> Role? {
        try? element.role()
    }

    /// Raw AXRole string. Prefer this when AXSwift6's Role enum is missing a
    /// case (notably AXMenuBarItem).
    static func roleString(for element: UIElement) -> String? {
        try? element.attribute(.role) as String?
    }

    /// Unions the frames of application menu titles in a menu bar element.
    /// Only menu item roles count: on macOS 27 the children include
    /// status-item hosts, which would make the leading pill swallow them.
    static func applicationMenuChildFrameUnion(for menuBar: UIElement) -> CGRect {
        children(for: menuBar).reduce(into: CGRect.null) { result, child in
            guard isEnabled(child), let childFrame = frame(for: child) else {
                return
            }
            switch roleString(for: child) {
            case "AXMenuBarItem", "AXMenuItem":
                result = result.union(childFrame)
            default:
                break
            }
        }
    }

    /// The element's AXTitle, when present. On macOS 27 most menu bar
    /// item elements leave this empty, so callers fall back to identifier.
    static func title(for element: UIElement) -> String? {
        try? element.attribute(.title)
    }

    /// The element's AXIdentifier. Thaw sets one on its control-item buttons
    /// so the macOS 27 AX enumeration can recognize them.
    static func identifier(for element: UIElement) -> String? {
        try? element.attribute(.identifier)
    }

    /// The element's accessibility description. Some status-item apps expose
    /// a stable semantic label here while AXTitle contains live metric text.
    static func description(for element: UIElement) -> String? {
        try? element.attribute(.description)
    }

    /// The element's AXValueDescription, where level-style items (battery,
    /// volume) tend to put the number their glyph only implies.
    static func valueDescription(for element: UIElement) -> String? {
        try? element.attribute(.valueDescription)
    }

    /// The element's AXValue, when it is a string. AXValue is untyped, so
    /// a numeric value simply yields nil here rather than a coerced string.
    static func stringValue(for element: UIElement) -> String? {
        try? element.attribute(.value)
    }

    static func pid(for element: UIElement) -> pid_t? {
        try? element.pid()
    }

    /// How long to wait for an owner to acknowledge a press. Must be set on the
    /// element: the app element's timeout does not propagate (default ~1.5 s).
    private static let pressMessagingTimeout = AXPrimitives.defaultMessagingTimeout

    /// Presses the element and returns whether its menu opened. Needed for
    /// Electron/Chromium tray items, which ignore synthetic clicks.
    ///
    /// AXSwift6 seals the raw element, so the action and owner go to the
    /// shared AXPrimitives.press ladder as closures.
    @discardableResult
    static func press(_ element: UIElement) -> Bool {
        try? element.setMessagingTimeout(pressMessagingTimeout)
        return AXPrimitives.press(
            perform: { () -> AXError in
                do {
                    try element.performAction(.press)
                    return .success
                } catch let error as AXError {
                    return error
                } catch {
                    return .failure
                }
            },
            ownerPID: { pid(for: element) }
        )
    }

    /// MenuBarAgent's extras menu bar, which publishes the system status items,
    /// read with the same messaging timeout.
    static func menuBarAgentExtrasBar() -> UIElement? {
        AXPrimitives.menuBarAgentExtrasBar().map { UIElement($0) }
    }

    /// element(at:) for callers that need the native element the AXSwift6
    /// wrapper seals, with the same timeout and the same off-main guard.
    static func nativeElement(at point: CGPoint) -> AXUIElement? {
        guard !WindowInfo.isUnsafeAccessibilityHitTest(at: point) else {
            return nil
        }
        return AXPrimitives.hitTestElement(at: point)
    }
}
