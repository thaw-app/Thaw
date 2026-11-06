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

    /// An item hidden now ages like a stable one at load, since a picture saved while it was visible lacks the hidden flag
    /// and an item hidden by turning off its Control Center module is never drawn again to be photographed.
    static func loadClassifications(
        _ classifications: [String: MenuBarItemVolatilityIndex.Volatility],
        hiddenIdentifiers: Set<String>
    ) -> [String: MenuBarItemVolatilityIndex.Volatility] {
        hiddenIdentifiers.reduce(into: classifications) { $0[$1] = .stable }
    }
}
