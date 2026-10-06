//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import Cocoa
import MenuBarModel
import ThawAXCore

nonisolated enum AXHelpers {
    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        // kAXTrustedCheckOptionPrompt's value; the global is not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// nil off the main thread when point is over a Thaw window. The hit-test
    /// is bounded: a hung app under the cursor would otherwise block it, and
    /// Thaw's main thread with it, indefinitely.
    static func element(at point: CGPoint) -> AXElement? {
        nativeElement(at: point).map(AXElement.init)
    }

    static func application(for runningApp: NSRunningApplication) -> AXElement? {
        let app = AXElement.application(runningApp.processIdentifier)
        // Without a timeout, an unresponsive app stalls enumeration
        // indefinitely in mach_msg.
        app.setMessagingTimeout(AXPrimitives.defaultMessagingTimeout)
        return app
    }

    static func extrasMenuBar(for app: AXElement) -> AXElement? {
        app.value(kAXExtrasMenuBarAttribute) as? AXElement
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
        var children: [AXElement] = []
    }

    /// Pass includingRole only for MenuBarAgent's bar. The walks also read Thaw's own bar off the
    /// main thread, where AppKit answers in-process and is not thread-safe, so that read stays minimal.
    static func menuBarChildAttributes(for element: AXElement, includingRole: Bool = false) -> MenuBarChildAttributes {
        let values = element.values((includingRole ? [kAXRoleAttribute] : []) + [
            frameAttribute, kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute,
        ])
        return MenuBarChildAttributes(
            role: values[kAXRoleAttribute] as? String,
            frame: values[frameAttribute] as? CGRect,
            identifier: values[kAXIdentifierAttribute] as? String,
            title: values[kAXTitleAttribute] as? String,
            accessibilityDescription: values[kAXDescriptionAttribute] as? String,
            children: values[kAXChildrenAttribute] as? [AXElement] ?? []
        )
    }

    /// The same reading below a status item. Never asks a menu for its
    /// children: that builds the menu, and some apps activate when it happens.
    ///
    /// - Parameter includingChildren: Whether to fetch the children at all,
    ///   for a walk that descends further. Never fetched for a menu.
    static func descendantAttributes(
        for element: AXElement,
        includingChildren: Bool = false
    ) -> MenuBarChildAttributes {
        let values = element.values([
            kAXRoleAttribute, frameAttribute, kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        ])
        let role = values[kAXRoleAttribute] as? String
        return MenuBarChildAttributes(
            role: role,
            frame: values[frameAttribute] as? CGRect,
            identifier: values[kAXIdentifierAttribute] as? String,
            title: values[kAXTitleAttribute] as? String,
            accessibilityDescription: values[kAXDescriptionAttribute] as? String,
            children: includingChildren && role != kAXMenuRole ? children(for: element) : []
        )
    }

    /// The application's normal menu bar (Apple menu + app menus).
    /// Unlike point hit-testing, this remains reliable when Thaw's overlay panel
    /// occupies the screen's menu-bar origin on macOS 27.
    static func menuBar(for app: AXElement) -> AXElement? {
        app.value(kAXMenuBarAttribute) as? AXElement
    }

    /// A menu bar's or a status item's children. Below a status item, read
    /// through descendantAttributes(for:includingChildren:) instead.
    static func children(for element: AXElement) -> [AXElement] {
        childrenIfAvailable(for: element) ?? []
    }

    /// The element's AXHelp attribute (tooltip/description string).
    static func help(for element: AXElement) -> String? {
        element.value(kAXHelpAttribute) as? String
    }

    static func childrenIfAvailable(for element: AXElement) -> [AXElement]? {
        element.value(kAXChildrenAttribute) as? [AXElement]
    }

    /// The element referenced by AXOverflowButton, when exposed. Containers
    /// such as the macOS 27 extras menu bar publish their overflow control as
    /// an attribute rather than as an ordinary child.
    static func overflowButton(for element: AXElement) -> AXElement? {
        element.value(kAXOverflowButtonAttribute) as? AXElement
    }

    /// The children of MenuBarAgent's extras bar that are its overflow
    /// chevron by role. See AXPrimitives.isMenuBarAgentOverflowRole(_:).
    static func overflowButtons(among children: [AXElement]) -> [AXElement] {
        children.filter { AXPrimitives.isMenuBarAgentOverflowRole(roleString(for: $0)) }
    }

    /// Whether the element advertises AXOverflowButton, or nil when its
    /// attribute list could not be read.
    static func supportsOverflowButton(_ element: AXElement) -> Bool? {
        element.attributeNames()?.contains(kAXOverflowButtonAttribute)
    }

    static func isEnabled(_ element: AXElement) -> Bool {
        enabledAttribute(element) ?? false
    }

    /// The raw AXEnabled attribute, or nil when not exposed. Unlike isEnabled,
    /// this tells "disabled" from "absent"; source-PID matching treats absent as enabled.
    static func enabledAttribute(_ element: AXElement) -> Bool? {
        element.value(kAXEnabledAttribute) as? Bool
    }

    static func frame(for element: AXElement) -> CGRect? {
        element.value(frameAttribute) as? CGRect
    }

    /// Raw AXRole string.
    static func roleString(for element: AXElement) -> String? {
        element.value(kAXRoleAttribute) as? String
    }

    /// Unions the frames of application menu titles in a menu bar element.
    /// Only menu item roles count: on macOS 27 the children include
    /// status-item hosts, which would make the leading pill swallow them.
    static func applicationMenuChildFrameUnion(for menuBar: AXElement) -> CGRect {
        children(for: menuBar).reduce(into: CGRect.null) { result, child in
            guard isEnabled(child), let childFrame = frame(for: child) else {
                return
            }
            switch roleString(for: child) {
            case kAXMenuBarItemRole, kAXMenuItemRole:
                result = result.union(childFrame)
            default:
                break
            }
        }
    }

    /// The element's AXTitle, when present. On macOS 27 most menu bar
    /// item elements leave this empty, so callers fall back to identifier.
    static func title(for element: AXElement) -> String? {
        element.value(kAXTitleAttribute) as? String
    }

    /// The element's AXIdentifier. Thaw sets one on its control-item buttons
    /// so the macOS 27 AX enumeration can recognize them.
    static func identifier(for element: AXElement) -> String? {
        element.value(kAXIdentifierAttribute) as? String
    }

    /// The element's accessibility description. Some status-item apps expose
    /// a stable semantic label here while AXTitle contains live metric text.
    static func description(for element: AXElement) -> String? {
        element.value(kAXDescriptionAttribute) as? String
    }

    /// The element's AXValueDescription, where level-style items (battery,
    /// volume) tend to put the number their glyph only implies.
    static func valueDescription(for element: AXElement) -> String? {
        element.value(kAXValueDescriptionAttribute) as? String
    }

    /// The element's AXValue, when it is a string. AXValue is untyped, so
    /// a numeric value simply yields nil here rather than a coerced string.
    static func stringValue(for element: AXElement) -> String? {
        element.value(kAXValueAttribute) as? String
    }

    static func pid(for element: AXElement) -> pid_t? {
        element.pid
    }

    /// Presses the element and returns whether its menu opened. Needed for
    /// Electron/Chromium tray items, which ignore synthetic clicks. The
    /// timeout must be set on the element: the app element's does not
    /// propagate (default ~1.5 s).
    @discardableResult
    static func press(_ element: AXElement) -> Bool {
        AXPrimitives.press(element.raw)
    }

    /// MenuBarAgent's extras menu bar, which publishes the system status items,
    /// read with the same messaging timeout.
    static func menuBarAgentExtrasBar() -> AXElement? {
        AXPrimitives.menuBarAgentExtrasBar().map(AXElement.init)
    }

    /// element(at:) as the raw element, with the same timeout and the same
    /// off-main guard.
    static func nativeElement(at point: CGPoint) -> AXUIElement? {
        guard !WindowInfo.isUnsafeAccessibilityHitTest(at: point) else {
            return nil
        }
        return AXPrimitives.hitTestElement(at: point)
    }

    private static let frameAttribute = "AXFrame"
}
