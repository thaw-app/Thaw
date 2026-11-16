//
//  GlyphStaleWidth.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    /// Whether picture no longer matches a width Thaw has for its item (GlyphRetakeLedger.widthIsStale).
    /// An item record can be older than the icon, as one listed without its process is, so any width
    /// that disagrees is enough.
    static nonisolated func oldPictureIsStale(_ picture: MenuBarItemGlyphCapture, itemWidths: [CGFloat?]) -> Bool {
        itemWidths.contains { width in
            width.map { GlyphRetakeLedger.widthIsStale(pictureWidth: picture.pointSize.width, itemWidth: $0) } ?? false
        }
    }

    /// The width of each item in Thaw's item list, by tag.
    func listedItemWidths() -> [MenuBarItemTag: CGFloat] {
        let items = appState?.itemManager.managedItems ?? []
        return Dictionary(items.map { ($0.tag, $0.bounds.width) }, uniquingKeysWith: { first, _ in first })
    }

    /// The width Thaw's item list has for tag's item, matching a record with an older window ID too.
    static nonisolated func listedWidth(of tag: MenuBarItemTag, in widths: [MenuBarItemTag: CGFloat]) -> CGFloat? {
        if let width = widths[tag] {
            return width
        }
        guard !tag.isSystemItem else { return nil }
        return widths.first { $0.key.matchesIgnoringWindowID(tag) }?.value
    }

    /// preferredRevealedImage(existing:candidate:recordedItemWidth:listedItemWidth:) for item, with the width
    /// Thaw recorded for it before the reveal and the one in listedWidths, Thaw's item list read since.
    static nonisolated func preferredRevealedImage(
        existing: MenuBarItemGlyphCapture,
        candidate: MenuBarItemGlyphCapture,
        revealing item: MenuBarItem,
        listedWidths: [MenuBarItemTag: CGFloat]
    ) -> MenuBarItemGlyphCapture {
        preferredRevealedImage(
            existing: existing,
            candidate: candidate,
            recordedItemWidth: item.bounds.width,
            listedItemWidth: listedWidth(of: item.tag, in: listedWidths)
        )
    }

    /// Merges a pass's new pictures into images through preferredCachedImage(existing:candidate:oldPictureIsStale:).
    /// A picture that no longer matches its item's listed width, as when an icon stops showing text,
    /// gives way to a much narrower one.
    func mergeNewImages(
        _ newImages: [MenuBarItemTag: MenuBarItemGlyphCapture],
        into images: inout [MenuBarItemTag: MenuBarItemGlyphCapture]
    ) {
        let itemWidths = listedItemWidths()
        for (tag, new) in newImages {
            images[tag] = images[tag].map { existing in
                let isStale = Self.oldPictureIsStale(existing, itemWidths: [Self.listedWidth(of: tag, in: itemWidths)])
                return Self.preferredCachedImage(existing: existing, candidate: new, oldPictureIsStale: isStale)
            } ?? new
        }
    }
}
