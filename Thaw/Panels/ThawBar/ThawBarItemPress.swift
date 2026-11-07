//
//  ThawBarItemPress.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// A press on a Thaw Bar item. It stays a click however long it's held, until the pointer moves
/// far enough to drag the panel, which is movable by its background.
nonisolated struct ThawBarItemPress: Equatable {
    static let dragDistance: CGFloat = 5

    private(set) var start: CGPoint?

    var isActive: Bool {
        start != nil
    }

    mutating func began(at location: CGPoint) {
        start = location
    }

    mutating func ended() {
        start = nil
    }

    /// Whether the pointer is still close enough to where the press began for its release to click.
    func isClick(at location: CGPoint) -> Bool {
        guard let start else { return false }
        return hypot(location.x - start.x, location.y - start.y) < Self.dragDistance
    }
}
