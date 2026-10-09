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
        guard !entries.isEmpty,
              entries.allSatisfy({ $0.frame.width > 0 && $0.frame.height > 0 })
        else { return nil }
        return Set(entries.map(\.ownerPID))
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
            // The item sits one or two levels down; the wrappers around it belong to the agent.
            // Stop at the first element the agent does not own: reading below it asks that app,
            // and for Thaw's own item AppKit would answer in-process, off the main thread.
            var leaf = child
            while pid(of: leaf) == agentPID, let next = children(of: leaf).first {
                leaf = next
            }
            return MenuBarAgentWindow.Entry(
                ownerPID: pid(of: leaf) ?? agentPID,
                frame: frame(of: child) ?? .zero
            )
        }
    }

    /// See MenuBarAgentWindow.drawnOwners(in:).
    static func menuBarAgentDrawnOwners(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> Set<pid_t>? {
        menuBarAgentWindowEntries(messagingTimeout: messagingTimeout).flatMap(MenuBarAgentWindow.drawnOwners(in:))
    }
}
