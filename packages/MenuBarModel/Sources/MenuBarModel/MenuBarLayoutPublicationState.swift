//
//  MenuBarLayoutPublicationState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Rejects cache publications that straddle a move or a newer authored edit.
public struct MenuBarLayoutPublicationState: Sendable {
    public private(set) var generation: UInt64 = 0
    private var activeMutations = 0

    public init() {}

    public mutating func invalidate() {
        generation &+= 1
    }

    public mutating func beginMutation() {
        invalidate()
        activeMutations += 1
    }

    public mutating func endMutation() {
        precondition(activeMutations > 0)
        activeMutations -= 1
        invalidate()
    }

    public func canPublish(generation: UInt64) -> Bool {
        activeMutations == 0 && self.generation == generation
    }
}
