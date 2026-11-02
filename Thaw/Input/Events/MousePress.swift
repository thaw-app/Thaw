//
//  MousePress.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// A mouse-down identified by when it happened, not by when Thaw got round to
/// handling it. The handling time is no use for this: opening the Thaw Bar keeps
/// the main thread busy for tens of milliseconds, so a repeat arrives that late.
nonisolated struct MousePress: Equatable {
    /// Sightings of one press closer together than this are the same press.
    /// Well under the fastest double-click a person can make, so it cannot eat
    /// the second click of the always-hidden gesture.
    static let sameness: TimeInterval = 0.02

    let type: NSEvent.EventType
    let timestamp: TimeInterval

    init(type: NSEvent.EventType, timestamp: TimeInterval) {
        self.type = type
        self.timestamp = timestamp
    }

    init(_ event: NSEvent) {
        self.init(type: event.type, timestamp: event.timestamp)
    }

    /// Whether this is another sighting of earlier rather than a new press.
    func isSamePress(as earlier: MousePress?) -> Bool {
        guard let earlier, earlier.type == type else {
            return false
        }
        return abs(timestamp - earlier.timestamp) < Self.sameness
    }
}

/// What the app has done with the most recent press, shared by the two monitors
/// that see each one: the Thaw Bar's outside-click monitor and the mouse-down
/// monitor behind show-on-click.
@MainActor
final class MousePressLedger {
    static let shared = MousePressLedger()

    private var currentPress: MousePress?
    private var dismissingPress: MousePress?

    /// Records press and returns whether it is new, false for a repeat sighting.
    func admit(_ press: MousePress) -> Bool {
        guard !press.isSamePress(as: currentPress) else {
            return false
        }
        currentPress = press
        return true
    }

    /// Records that press closed the Thaw Bar from outside it.
    func noteDismissal(by press: MousePress) {
        dismissingPress = press
    }

    /// Whether the press being handled has already closed the Thaw Bar.
    var currentPressDismissedBar: Bool {
        currentPress?.isSamePress(as: dismissingPress) ?? false
    }
}
