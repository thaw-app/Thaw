//
//  KnownIdentitySeeding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Which identities a cache pass learns as known without anything placing them:
/// the new identity of a window already known under another one, such as after
/// its source PID resolved. A window only seen, not known, on the last pass stays
/// new, or one pass that didn't place a brand-new icon would hide it from every
/// later pass.
nonisolated enum KnownIdentitySeeding {
    struct Item {
        let windowID: CGWindowID
        let identifier: String
        let hasSourcePID: Bool
    }

    static func learned(current: [Item], previousIdentifiers: [CGWindowID: String], known: Set<String>) -> [String] {
        current.compactMap { item in
            guard item.hasSourcePID,
                  let previous = previousIdentifiers[item.windowID],
                  known.contains(previous)
            else { return nil }
            return item.identifier
        }
    }
}
