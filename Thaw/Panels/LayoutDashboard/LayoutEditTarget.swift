//
//  LayoutEditTarget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The menu bar a Layout window edits: one display, on one Space.
nonisolated struct LayoutEditTarget: Equatable {
    /// Survives reconnecting, unlike the display ID; nil when macOS gives no UUID.
    var displayUUID: String?
    var displayID: CGDirectDisplayID
    /// The Space's persistent key, or nil before the window server lists it.
    var spaceKey: String?
    var displayName: String
    var spaceName: String?

    /// Whether other names the same menu bar. Names are labels, so they don't count.
    func isSameBar(as other: LayoutEditTarget) -> Bool {
        let sameDisplay = displayUUID != nil && other.displayUUID != nil
            ? displayUUID == other.displayUUID
            : displayID == other.displayID
        // An unlisted Space can't be told apart, so it doesn't block editing.
        let sameSpace = spaceKey == nil || other.spaceKey == nil || spaceKey == other.spaceKey
        return sameDisplay && sameSpace
    }
}

/// Keeps a Layout window on the bar it opened for. The bars always show the
/// live menu bar, so away from that bar they go read-only instead of editing another.
nonisolated struct LayoutTargetPin: Equatable {
    enum State: Equatable {
        case editing
        /// The person is on another Space or display, named by current.
        case elsewhere(current: LayoutEditTarget)
    }

    private(set) var pinned: LayoutEditTarget
    private(set) var current: LayoutEditTarget

    init(_ target: LayoutEditTarget) {
        pinned = target
        current = target
    }

    var state: State {
        current.isSameBar(as: pinned) ? .editing : .elsewhere(current: current)
    }

    var isEditable: Bool {
        state == .editing
    }

    /// Records where the person is now. Names refresh on the pinned target too.
    mutating func observe(_ target: LayoutEditTarget) {
        current = target
        if target.isSameBar(as: pinned) {
            pinned = target
        }
    }

    /// Edits the bar the person is on instead.
    mutating func retargetToCurrent() {
        pinned = current
    }
}
