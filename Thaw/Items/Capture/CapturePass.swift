//
//  CapturePass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Capture Pass

    /// Everything one capture pass learned.
    ///
    /// The invalidation sets carry reads that prove the cached entry wrong;
    /// without them a poisoned entry would survive every later pass.
    struct CapturePass {
        /// Crops this pass is willing to publish, keyed by item tag.
        var captured = [MenuBarItemTag: MenuBarItemGlyphCapture]()

        /// Items this pass could not read pixels for. Retained rather than
        /// dropped so failure strikes and diagnostics can account for them.
        var unreadable = [MenuBarItem]()

        /// Tags this pass proved have no usable glyph, so the app icon shows
        /// instead of a stale screenshot.
        var invalidatedTags = Set<MenuBarItemTag>()

        /// Tags dropped even when the prior looks settled. Governable system
        /// extras are excluded: their glyph from before removal is still valid.
        var unconditionallyInvalidatedTags = Set<MenuBarItemTag>()

        /// Crop failures this pass observed, struck against the ledger only
        /// once the pass is allowed to publish.
        var failedCaptureItems = [MenuBarItem]()

        /// Items whose crop succeeded, forgiven in the ledger on the same terms.
        var recoveredItems = [MenuBarItem]()

        /// Tags this pass attempted whatever their failure record said. The
        /// record itself is forgotten on the same terms, so a discarded pass
        /// leaves it alone and the next pass sets it aside again.
        var forgivenTags = Set<MenuBarItemTag>()

        /// Folds a later section's result into this pass.
        mutating func absorb(_ section: CapturePass) {
            captured.merge(section.captured) { _, new in new }
            unreadable += section.unreadable
            invalidatedTags.formUnion(section.invalidatedTags)
            unconditionallyInvalidatedTags.formUnion(section.unconditionallyInvalidatedTags)
            failedCaptureItems += section.failedCaptureItems
            recoveredItems += section.recoveredItems
            forgivenTags.formUnion(section.forgivenTags)
        }
    }
}
