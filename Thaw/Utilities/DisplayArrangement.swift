//
//  DisplayArrangement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Which displays are connected, where each one sits, and which one is main.
/// A swapped display, a new arrangement or another main display moves every bar without changing the count.
nonisolated struct DisplayArrangement: Equatable {
    /// How the arrangement changed between two readings.
    enum Change: Equatable {
        case unchanged
        case connected
        case disconnected
        /// Same number of displays, but other ones, in other places, or with another main display.
        case rearranged

        /// The reason given to the settling period that follows.
        var settlingReason: String {
            switch self {
            case .unchanged: "displayUnchanged"
            case .connected: "displayConnect"
            case .disconnected: "displayDisconnect"
            case .rearranged: "displayArrangement"
            }
        }

        /// What happened, for the log.
        var logDescription: String {
            switch self {
            case .unchanged: "Display arrangement unchanged"
            case .connected: "Display connected"
            case .disconnected: "Display disconnected"
            case .rearranged: "Display arrangement changed"
            }
        }
    }

    /// Each display's frame in global coordinates, by display ID.
    let frames: [CGDirectDisplayID: CGRect]
    let mainDisplayID: CGDirectDisplayID?

    /// How this arrangement differs from the one it replaced, judged by count first.
    func change(from previous: Self) -> Change {
        if frames.count > previous.frames.count {
            return .connected
        }
        if frames.count < previous.frames.count {
            return .disconnected
        }
        return self == previous ? .unchanged : .rearranged
    }

    /// The displays Thaw manages right now.
    @MainActor
    static var current: Self {
        let screens = NSScreen.managedScreens
        return Self(
            frames: Dictionary(screens.map { ($0.displayID, CGDisplayBounds($0.displayID)) }) { first, _ in first },
            mainDisplayID: screens.isEmpty ? nil : CGMainDisplayID()
        )
    }
}

/// Remembers the last arrangement seen, so each reading says how the displays changed since.
nonisolated struct DisplayArrangementWatch {
    private(set) var last: DisplayArrangement

    init(_ initial: DisplayArrangement) {
        last = initial
    }

    /// Takes a new reading and returns how it differs from the last one.
    mutating func update(to arrangement: DisplayArrangement) -> DisplayArrangement.Change {
        defer { last = arrangement }
        return arrangement.change(from: last)
    }
}
