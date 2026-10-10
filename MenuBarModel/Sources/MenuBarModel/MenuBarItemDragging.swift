//
//  MenuBarItemDragging.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics

/// How a process-addressed drag ended.
///
/// As with MenuBarItemPressOutcome, only the verdict and a description
/// cross the seam; the caller verifies the bar afterwards regardless.
public struct MenuBarItemDragOutcome: Sendable {
    /// Whether every phase of the gesture was accepted for delivery.
    public let wasDelivered: Bool
    /// The platform's own account of the attempt, for the log line.
    public let diagnosticDescription: String

    public init(wasDelivered: Bool, diagnosticDescription: String) {
        self.wasDelivered = wasDelivered
        self.diagnosticDescription = diagnosticDescription
    }
}

/// Reorders a menu bar item with a Command-drag delivered to the menu bar's
/// owning process, without entering the global HID stream or moving the
/// user's pointer.
public protocol MenuBarItemDragging: Sendable {
    /// Whether the addressed path resolved on this system.
    var isAvailable: Bool { get }

    /// Drags from start to end, both in top-left CG-global coordinates,
    /// addressed to the process ownerPID that hosts the menu bar.
    func commandDrag(ownerPID: pid_t, from start: CGPoint, to end: CGPoint) async -> MenuBarItemDragOutcome

    /// Window-addressed variant: delivered to the item's own window, with
    /// windowFrame converting the global points into window-local ones.
    ///
    /// A requirement rather than an extension method so existential dispatch
    /// reaches the conformer's override instead of the point-resolving fallback.
    func commandDrag(
        ownerPID: pid_t,
        windowID: CGWindowID,
        windowFrame: CGRect,
        from start: CGPoint,
        to end: CGPoint
    ) async -> MenuBarItemDragOutcome
}

public extension MenuBarItemDragging {
    /// Drops the window hint and reuses the point-resolving drag. On macOS 27
    /// that variant cannot find a host window, so conformers should override.
    func commandDrag(
        ownerPID: pid_t,
        windowID _: CGWindowID,
        windowFrame _: CGRect,
        from start: CGPoint,
        to end: CGPoint
    ) async -> MenuBarItemDragOutcome {
        await commandDrag(ownerPID: ownerPID, from: start, to: end)
    }
}
