//
//  MenuBarItemPressing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics

/// An accessibility element and the process that owns it.
///
/// Unchecked Sendable: the AX API is thread-safe and a blocking press has to
/// leave the caller's actor. The owner attributes an opened menu to the item.
public struct MenuBarItemPressTarget: @unchecked Sendable {
    public let element: AXUIElement
    public let ownerPID: pid_t

    public init(element: AXUIElement, ownerPID: pid_t) {
        self.element = element
        self.ownerPID = ownerPID
    }
}

/// How a press attempt ended.
///
/// Only the verdict and a description cross the seam; which rung answered is
/// for the log line, and no caller branches on it.
public struct MenuBarItemPressOutcome: Sendable {
    /// Whether the item's menu opened.
    public let didOpen: Bool

    /// The platform's own account of the attempt, for the log line.
    public let diagnosticDescription: String

    public init(didOpen: Bool, diagnosticDescription: String) {
        self.didOpen = didOpen
        self.diagnosticDescription = diagnosticDescription
    }
}

/// Opens a menu bar item's menu without posting into the global HID stream.
///
/// Tried before the synthetic path, which warps the cursor (visible jitter)
/// and lands on whatever is under the cursor by then.
public protocol MenuBarItemPressing: Sendable {
    /// Presses target, falling back to a process-targeted click at point
    /// when the accessibility press does not open the menu.
    ///
    /// Pass nil for point to skip the fallback, when the frame is unknown or
    /// the owner's response to a synthesized record is not understood.
    func press(_ target: MenuBarItemPressTarget, at point: CGPoint?) async -> MenuBarItemPressOutcome
}
