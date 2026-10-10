//
//  MenuBarItemEventType.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - MenuBarItemEventType

/// One half of a synthetic click aimed at a menu bar item.
///
/// A click is always two events, a press and a release, and every field the
/// window server reads follows from which of the six this is: the Core
/// Graphics event type, the button it is attributed to, and whether it opens
/// or closes a click. CGEvent.menuBarItemEvent(item:source:type:location:)
/// reads all of them back out.
///
/// Rearranging an item does not go through here. That path is a command-drag
/// owned by SyntheticMoveEngine, which builds its own events.
nonisolated enum MenuBarItemEventType {
    case leftMouseDown
    case leftMouseUp
    case rightMouseDown
    case rightMouseUp
    case otherMouseDown
    case otherMouseUp

    /// The press and release that a complete click with button is made of.
    ///
    /// Buttons past the right one all share the other events, matching how
    /// Core Graphics reports them.
    static func pair(for button: CGMouseButton) -> (down: MenuBarItemEventType, up: MenuBarItemEventType) {
        switch button {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    /// The Core Graphics event type to synthesize.
    var cgEventType: CGEventType {
        switch self {
        case .leftMouseDown: .leftMouseDown
        case .leftMouseUp: .leftMouseUp
        case .rightMouseDown: .rightMouseDown
        case .rightMouseUp: .rightMouseUp
        case .otherMouseDown: .otherMouseDown
        case .otherMouseUp: .otherMouseUp
        }
    }

    /// The button the event is attributed to.
    var cgMouseButton: CGMouseButton {
        switch self {
        case .leftMouseDown, .leftMouseUp: .left
        case .rightMouseDown, .rightMouseUp: .right
        case .otherMouseDown, .otherMouseUp: .center
        }
    }

    /// What goes into the event's click-state field: a press opens a click
    /// and counts as one, a release closes it and counts as none.
    var clickState: Int64 {
        switch self {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: 1
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: 0
        }
    }
}
