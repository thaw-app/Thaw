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

    /// One of the agent's windows: a display's bar, and what is drawn on it.
    public struct Bar: Equatable, Sendable {
        /// The window's frame, or nil when it could not be read.
        public let frame: CGRect?
        public let entries: [Entry]

        public init(frame: CGRect?, entries: [Entry]) {
            self.frame = frame
            self.entries = entries
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

    /// Which of the agent's windows is the bar of display: the first whose middle lies on it. A nil frame matches
    /// none. Apple documents no window order, and on the one Mac checked the first was not the main display's.
    public static func windowIndex(onDisplay display: CGRect, among frames: [CGRect?]) -> Int? {
        frames.firstIndex { frame in
            frame.map { display.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? false
        }
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
    /// The window is the agent's first, which can be any display's bar, unless display names the bar to read.
    static func menuBarAgentWindowEntries(
        onDisplay display: CGRect? = nil,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> [MenuBarAgentWindow.Entry]? {
        autoreleasepool {
            guard let agentPID = menuBarAgentPID() else { return nil }
            let agent = AXUIElementCreateApplication(agentPID)
            AXUIElementSetMessagingTimeout(agent, messagingTimeout)
            let windows = copyAttribute(agent, kAXWindowsAttribute) as? [AXUIElement] ?? []
            let index = display.map { MenuBarAgentWindow.windowIndex(onDisplay: $0, among: windows.map(frame(of:))) } ?? windows.indices.first
            guard let window = index.map({ windows[$0] }) else {
                return nil
            }
            return menuBarAgentEntries(in: window, agentPID: agentPID)
        }
    }

    /// One Bar per window of MenuBarAgent, or nil when the agent cannot be read. For a diagnostic report:
    /// a bar mid-change is included as it is.
    static func menuBarAgentBars(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> [MenuBarAgentWindow.Bar]? {
        autoreleasepool {
            guard let agentPID = menuBarAgentPID() else { return nil }
            let agent = AXUIElementCreateApplication(agentPID)
            AXUIElementSetMessagingTimeout(agent, messagingTimeout)
            guard let windows = copyAttribute(agent, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
            return windows.map { window in
                MenuBarAgentWindow.Bar(frame: frame(of: window), entries: menuBarAgentEntries(in: window, agentPID: agentPID))
            }
        }
    }

    private static func menuBarAgentEntries(in window: AXUIElement, agentPID: pid_t) -> [MenuBarAgentWindow.Entry] {
        children(of: window).map { child in
            MenuBarAgentWindow.Entry(
                ownerPID: MenuBarAgentWindow.ownerPID(of: child, agentPID: agentPID, pid: pid(of:), children: children(of:)),
                frame: frame(of: child) ?? .zero
            )
        }
    }

    /// The bar as MenuBarAgent draws it right now, or nil when it could not be read or is mid-change.
    static func menuBarAgentSettledEntries(
        onDisplay display: CGRect? = nil,
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> [MenuBarAgentWindow.Entry]? {
        menuBarAgentWindowEntries(onDisplay: display, messagingTimeout: messagingTimeout).flatMap(MenuBarAgentWindow.settled)
    }

    /// See MenuBarAgentWindow.drawnOwners(in:).
    static func menuBarAgentDrawnOwners(
        messagingTimeout: Float = defaultMessagingTimeout
    ) -> Set<pid_t>? {
        menuBarAgentWindowEntries(messagingTimeout: messagingTimeout).flatMap(MenuBarAgentWindow.drawnOwners(in:))
    }
}
