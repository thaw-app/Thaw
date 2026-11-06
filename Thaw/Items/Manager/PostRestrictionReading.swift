//
//  PostRestrictionReading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import ThawCapture

/// What the post-restriction repair reads before it takes the repair lane: the items, and one
/// picture of the bar to tell which of them drew nothing.
///
/// The picture can wait for the capture service to start. Taken inside the lane, that wait held the
/// lane for 5 and 7 seconds with nothing written, and a reveal's restore queued behind it was dropped.
struct PostRestrictionReading {
    let items: [MenuBarItem]
    let displayID: CGDirectDisplayID
    /// Nil when the capture was refused or failed. Nothing is called blank then.
    let barCapture: ScreenCapture.MenuBarHostingCapture?

    /// Whether the picture can answer for this display. A reading of another display is not used.
    func covers(_ display: CGDirectDisplayID) -> Bool {
        displayID == display
    }

    /// The given items that drew nothing in the picture.
    func blankTags(among items: [MenuBarItem]) -> Set<MenuBarItemTag> {
        guard !items.isEmpty, let barCapture else { return [] }
        return MenuBarItemImageCache.blankTags(in: items, from: barCapture)
    }
}
