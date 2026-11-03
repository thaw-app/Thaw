//
//  MousePress.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// A mouse-down identified by its event timestamp. Handling time can't identify
/// it: opening the Thaw Bar can hold back a repeat by tens of milliseconds.
nonisolated struct MousePress: Equatable {
    /// Sightings closer than this are one press. Well under the fastest
    /// double-click, so the always-hidden gesture keeps its second click.
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

/// The latest press, shared by the Thaw Bar's outside-click monitor and the
/// show-on-click mouse-down monitor, which both see each one.
@MainActor
final class MousePressLedger {
    static let shared = MousePressLedger()

    private var currentPress: MousePress?
    private var dismissingPress: MousePress?

    /// Records press and returns false for a repeat sighting.
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
