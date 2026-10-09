//
//  MenuBarAgentWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics

/// What MenuBarAgent's own window says is drawn on the menu bar.
///
/// The window has one child per item on the bar, Apple's and other apps' alike, and the element
/// inside each child belongs to the app that owns the item. One read of one process therefore
/// says which apps have something on the bar, without asking any of them. Hidden items are not
/// in it.
public enum MenuBarAgentWindow {
    public struct Entry: Equatable, Sendable {
        public let ownerPID: pid_t
        public let frame: CGRect

        public init(ownerPID: pid_t, frame: CGRect) {
            self.ownerPID = ownerPID
            self.frame = frame
        }
    }

    /// The apps with an item drawn on the bar, or nil when the read cannot be trusted.
    ///
    /// While an item leaves, the window keeps an empty child for it for a moment: no owner of its
    /// own and no size. A read that holds one was taken mid-change, and so was an empty one.
    public static func drawnOwners(in entries: [Entry]) -> Set<pid_t>? {
        settled(entries).map { Set($0.map(\.ownerPID)) }
    }

    /// The entries as given when they describe a bar at rest, or nil when the read was empty or
    /// taken mid-change. Two settled reads that are equal describe a bar that has not moved.
    public static func settled(_ entries: [Entry]) -> [Entry]? {
        guard !entries.isEmpty,
              entries.allSatisfy({ $0.frame.width > 0 && $0.frame.height > 0 })
        else { return nil }
        return entries
    }

    /// The process that owns the item inside one child of the window.
    ///
    /// The wrappers around an item belong to the agent, and the first element that does not is the
    /// item itself. The descent stops there and asks that element nothing. An item of this app's own
    /// is answered in-process, on the calling thread, and AppKit's accessibility is main-thread only:
    /// asking it for its children from a background walk crashed the app.
    public static func ownerPID<Element>(
        of child: Element,
        agentPID: pid_t,
        pid: (Element) -> pid_t?,
        children: (Element) -> [Element]
    ) -> pid_t {
        var element = child
        while true {
            guard let owner = pid(element) else { return agentPID }
            guard owner == agentPID else { return owner }
            guard let next = children(element).first else { return agentPID }
            element = next
        }
    }
}

public extension AXPrimitives {
    /// One entry per child of MenuBarAgent's window, or nil when the agent or its window cannot be read.
    static func menuBarAgentWindowEntries(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> [MenuBarAgentWindow.Entry]? {
        guard let agentPID = menuBarAgentPID() else { return nil }
        let agent = AXUIElementCreateApplication(agentPID)
        AXUIElementSetMessagingTimeout(agent, messagingTimeout)
        guard let window = (copyAttribute(agent, kAXWindowsAttribute) as? [AXUIElement])?.first else {
            return nil
        }
        return children(of: window).map { child in
            MenuBarAgentWindow.Entry(
                ownerPID: MenuBarAgentWindow.ownerPID(of: child, agentPID: agentPID, pid: pid(of:), children: children(of:)),
                frame: frame(of: child) ?? .zero
            )
        }
    }

    /// The bar as MenuBarAgent draws it right now, or nil when it could not be read or is mid-change.
    static func menuBarAgentSettledEntries(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> [MenuBarAgentWindow.Entry]? {
        menuBarAgentWindowEntries(messagingTimeout: messagingTimeout).flatMap(MenuBarAgentWindow.settled)
    }

    /// See MenuBarAgentWindow.drawnOwners(in:).
    static func menuBarAgentDrawnOwners(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> Set<pid_t>? {
        menuBarAgentWindowEntries(messagingTimeout: messagingTimeout).flatMap(MenuBarAgentWindow.drawnOwners(in:))
    }
}
