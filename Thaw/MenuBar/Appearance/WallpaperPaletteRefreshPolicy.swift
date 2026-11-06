//
//  WallpaperPaletteRefreshPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// A palette costs a full-wallpaper capture, so strip samples reuse it until one of its inputs changes.
/// Pure and value-based; the menu bar manager supplies the live inputs.
nonisolated enum WallpaperPaletteRefreshPolicy {
    /// What a display's palette was captured from.
    struct Source: Equatable {
        /// Advances on wallpaper-index, Space and display-parameter changes.
        let wallpaperGeneration: Int

        /// The strip average, which moves with wallpapers that change without any notification.
        let stripColor: CGColor

        /// The wallpaper window's bounds; a resolution or arrangement change moves them.
        let wallpaperBounds: CGRect

        /// The backdrop composited into the capture differs between light and dark.
        let isDarkAppearance: Bool
    }

    enum Reason: Equatable {
        /// Nothing usable was captured from this display yet.
        case noPalette
        case wallpaperChanged
        case displayChanged
        case appearanceChanged

        /// Covers wallpapers that drift without moving the strip or posting anything.
        case fallbackIntervalElapsed
    }

    /// Why the palette must be captured again, or nil to reuse it.
    /// A nil previous means the display has no palette; a nil age is treated as overdue.
    static func refreshReason(
        previous: Source?,
        current: Source,
        timeSinceLastRefresh: Duration?,
        fallbackInterval: Duration
    ) -> Reason? {
        guard let previous else { return .noPalette }
        if previous.wallpaperGeneration != current.wallpaperGeneration || previous.stripColor != current.stripColor {
            return .wallpaperChanged
        }
        if previous.wallpaperBounds != current.wallpaperBounds {
            return .displayChanged
        }
        if previous.isDarkAppearance != current.isDarkAppearance {
            return .appearanceChanged
        }
        guard let timeSinceLastRefresh, timeSinceLastRefresh < fallbackInterval else {
            return .fallbackIntervalElapsed
        }
        return nil
    }
}
