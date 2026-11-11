//
//  SpaceChangeCoalescer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// A signal that a Space may have changed, from the window server or from NSWorkspace.
nonisolated enum SpaceSignal: Sendable, Equatable {
    case activeSpace
    case spaceList
}

/// A Space change delivered once to subscribers.
nonisolated enum SpaceChange: Sendable, Equatable {
    case activeSpace(CGSSpaceID)
    case spaceList
}

/// Turns the two window server events and the NSWorkspace notification that
/// follow one switch into a single change.
nonisolated struct SpaceChangeCoalescer {
    /// Signals this close to the last delivered one count as the same change.
    static let duplicateWindow: Duration = .seconds(1)

    private var lastActive: (spaceID: CGSSpaceID, shown: Set<CGSSpaceID>, at: ContinuousClock.Instant)?

    /// The change to deliver for signal, or nil when it repeats one already delivered.
    /// - Parameters:
    ///   - activeSpaceID: The active Space as read when the signal arrived.
    ///   - shown: The Space each display showed when the signal arrived. A switch on a display
    ///     that isn't the active one leaves the active Space alone and changes only this.
    ///   - now: When the signal arrived.
    mutating func admit(
        _ signal: SpaceSignal,
        activeSpaceID: CGSSpaceID,
        shown: Set<CGSSpaceID> = [],
        at now: ContinuousClock.Instant
    ) -> SpaceChange? {
        switch signal {
        case .activeSpace:
            if let lastActive, lastActive.spaceID == activeSpaceID, lastActive.shown == shown, lastActive.at.duration(to: now) < Self.duplicateWindow {
                return nil
            }
            lastActive = (activeSpaceID, shown, now)
            return .activeSpace(activeSpaceID)
        case .spaceList:
            // Nothing tells two list events apart, so subscribers debounce them instead.
            return .spaceList
        }
    }
}
