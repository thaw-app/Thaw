//
//  DisplayTopologyChange.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The connected displays and the one whose menu bar is active, at one moment.
public struct DisplayTopologySnapshot: Equatable, Sendable {
    public struct Display: Equatable, Sendable {
        public var id: CGDirectDisplayID
        public var frame: CGRect

        public init(id: CGDirectDisplayID, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    public var displays: [Display]
    /// Nil while macOS is between layouts and names no connected display.
    public var activeDisplayID: CGDirectDisplayID?

    public init(displays: [Display], activeDisplayID: CGDirectDisplayID?) {
        self.displays = displays
        self.activeDisplayID = activeDisplayID
    }
}

/// What changed between two snapshots. A display swap is both connected and
/// disconnected, so it is not mistaken for no change by a count comparison.
public struct DisplayTopologyChange: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let connected = DisplayTopologyChange(rawValue: 1 << 0)
    public static let disconnected = DisplayTopologyChange(rawValue: 1 << 1)
    /// A display kept its identity but moved or resized.
    public static let rearranged = DisplayTopologyChange(rawValue: 1 << 2)
    /// The active menu bar moved to another connected display.
    public static let activeBarMoved = DisplayTopologyChange(rawValue: 1 << 3)

    public static func between(
        _ previous: DisplayTopologySnapshot,
        _ current: DisplayTopologySnapshot
    ) -> DisplayTopologyChange {
        let before = Dictionary(previous.displays.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(current.displays.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        var change: DisplayTopologyChange = []
        if after.keys.contains(where: { before[$0] == nil }) {
            change.insert(.connected)
        }
        if before.keys.contains(where: { after[$0] == nil }) {
            change.insert(.disconnected)
        }
        if after.contains(where: { id, frame in before[id].map { $0 != frame } ?? false }) {
            change.insert(.rearranged)
        }
        if let active = current.activeDisplayID, active != previous.activeDisplayID {
            change.insert(.activeBarMoved)
        }
        return change
    }
}
