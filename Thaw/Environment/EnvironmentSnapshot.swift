//
//  EnvironmentSnapshot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

nonisolated enum EnvironmentChange: String, Equatable, Sendable {
    case displayAdded
    case displayRemoved
    /// The same number of displays, but other ones, in other places, or with another main display.
    case rearranged
    /// The same displays and main display, with at least one display at a new size.
    case resolutionOnly
    case none

    /// A new size counts as a resolution change even when a neighbour's origin shifts, because macOS
    /// moves the neighbours to keep them adjacent.
    init(from previous: DisplayArrangement, to current: DisplayArrangement) {
        if current.frames.count > previous.frames.count {
            self = .displayAdded
        } else if current.frames.count < previous.frames.count {
            self = .displayRemoved
        } else if current == previous {
            self = .none
        } else if Set(current.frames.keys) == Set(previous.frames.keys), current.mainDisplayID == previous.mainDisplayID, current.frames.contains(where: { id, frame in previous.frames[id]?.size != frame.size }) {
            self = .resolutionOnly
        } else {
            self = .rearranged
        }
    }
}

/// The generation rises once per settled change, so a reader can tell one change from the next.
@MainActor
final class EnvironmentSnapshot {
    private(set) var generation = 0
    private(set) var arrangement: DisplayArrangement

    init(arrangement: DisplayArrangement) {
        self.arrangement = arrangement
    }

    @discardableResult
    func settle(on newArrangement: DisplayArrangement) -> EnvironmentChange {
        let change = EnvironmentChange(from: arrangement, to: newArrangement)
        if change != .none {
            arrangement = newArrangement
            generation += 1
        }
        return change
    }
}
