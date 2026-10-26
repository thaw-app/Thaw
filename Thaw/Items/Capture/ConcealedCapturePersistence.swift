//
//  ConcealedCapturePersistence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// A hidden item's glyph is only captured while revealed, so without it on disk a relaunch shows app icons
/// until the next reveal. Visible glyphs are recaptured within seconds, so changes to only those skip the write.
nonisolated enum ConcealedCapturePersistence {
    /// Whether a hidden item's image changed. Only hidden tags are compared, since comparing can read pixels.
    static func shouldSave(
        capturedTags: some Sequence<MenuBarItemTag>,
        concealedIdentifiers: Set<String>,
        imageChanged: (MenuBarItemTag) -> Bool
    ) -> Bool {
        guard !concealedIdentifiers.isEmpty else { return false }
        return capturedTags.contains { concealedIdentifiers.contains($0.tagIdentifier) && imageChanged($0) }
    }
}
