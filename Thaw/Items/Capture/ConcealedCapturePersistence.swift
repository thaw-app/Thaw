//
//  ConcealedCapturePersistence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Whether a capture pass is worth writing to disk.
///
/// A hidden item's glyph can only be captured while it is revealed, and the live loop never refreshes it,
/// so a relaunch without that capture on disk shows app icons until the next reveal. A visible item's
/// glyph is captured again within seconds of any open, so passes that change only those skip the write.
nonisolated enum ConcealedCapturePersistence {
    static func shouldSave(changedTags: some Sequence<MenuBarItemTag>, concealedIdentifiers: Set<String>) -> Bool {
        changedTags.contains { concealedIdentifiers.contains($0.tagIdentifier) }
    }
}
