//
//  IgnoredPreferredWrites.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Items whose preferred-position write MenuBarAgent ignored, so a reveal does not write them again
/// until something has changed.
nonisolated struct IgnoredPreferredWrites {
    /// What the bar looked like when the write was ignored. A change to any of it clears the item.
    struct Circumstances: Equatable {
        let layout: [MenuBarSectionName: [String]]
        let frame: CGRect
        let displayID: CGDirectDisplayID
    }

    private var ignored: [String: Circumstances] = [:]

    mutating func noteIgnored(_ id: String, under circumstances: Circumstances) {
        ignored[id] = circumstances
    }

    /// Whether to skip the item. A change in circumstances forgets it, so it is tried again.
    mutating func skips(_ id: String, under circumstances: Circumstances) -> Bool {
        guard let noted = ignored[id] else { return false }
        guard noted == circumstances else {
            ignored[id] = nil
            return false
        }
        return true
    }

    mutating func removeAll() {
        ignored.removeAll()
    }
}
