//
//  LayoutBanner.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import MenuBarModel

/// The one warning the Layout pane shows above its bars.
///
/// Several can be true at once, and stacked they push the bars off the first screen. The pane shows the
/// most serious and leaves the rest until it is dealt with.
nonisolated enum LayoutBanner: Equatable {
    /// macOS has Thaw switched off in its menu bar settings, so nothing in the pane can work.
    case deniedBySystem
    /// Some running apps' items cannot be read.
    case outOfReach
    /// macOS is hiding items behind its own overflow arrow because the bar has no room for them.
    case outOfRoom
    /// Icons are drawn from app icons because Screen Recording is off.
    case noScreenRecording

    static func mostSerious(
        isDeniedBySystem: Bool,
        hasItemsOutOfReach: Bool,
        isOutOfRoom: Bool,
        hasScreenRecording: Bool
    ) -> LayoutBanner? {
        if isDeniedBySystem { return .deniedBySystem }
        if hasItemsOutOfReach { return .outOfReach }
        if isOutOfRoom { return .outOfRoom }
        return hasScreenRecording ? nil : .noScreenRecording
    }

    /// Whether tips may sit beside this warning. A tip under a warning that something is broken is noise.
    static func allowsTips(beside banner: LayoutBanner?) -> Bool {
        banner == nil || banner == .noScreenRecording
    }

    /// The Visible items macOS is not drawing, in bar order.
    static func itemsNotDrawn(visibleItems: [MenuBarItem], notDrawnTags: Set<MenuBarItemTag>) -> [MenuBarItem] {
        visibleItems.filter { notDrawnTags.contains($0.tag) }
    }

    /// The names of the Visible items macOS is not drawing, in bar order, each name once.
    static func namesNotDrawn(visibleItems: [MenuBarItem], notDrawnTags: Set<MenuBarItemTag>) -> [String] {
        Array(itemsNotDrawn(visibleItems: visibleItems, notDrawnTags: notDrawnTags).map(\.displayName).uniqued())
    }
}
