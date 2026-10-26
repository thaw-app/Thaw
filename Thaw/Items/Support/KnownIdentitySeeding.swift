//
//  KnownIdentitySeeding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// A window known under an earlier identity (before its source PID resolved) is known under its new one;
/// a window only seen stays new.
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
