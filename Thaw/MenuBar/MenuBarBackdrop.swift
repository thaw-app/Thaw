//
//  MenuBarBackdrop.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawCapture

/// What the transparent macOS 27 menu bar is drawn over, for anything painted over it.
///
/// Nothing is kept here, since a picture can hold other apps' windows. Reads can show
/// the recording indicator, and a full-screen app under the bar would be captured,
/// so read only when the bar can be seen. Including the bar itself renders flat grey.
@MainActor
final class MenuBarBackdrop {
    /// A picture of what is behind part of the bar.
    struct Strip {
        /// The strip in CG-global coordinates.
        let rect: CGRect
        let image: CGImage

        /// The part of the strip under cgRect, as a unit rect for a layer's
        /// contentsRect.
        func contentsRect(for cgRect: CGRect) -> CGRect {
            CGRect(
                x: (cgRect.minX - rect.minX) / rect.width,
                y: (cgRect.minY - rect.minY) / rect.height,
                width: cgRect.width / rect.width,
                height: cgRect.height / rect.height
            )
        }
    }

    /// Composites whatever lies below the menu bar inside cgRect, which may
    /// reach below the bar (the wallpaper palette reads the whole wallpaper).
    func capture(
        _ cgRect: CGRect,
        resolution: CGWindowImageOption = .bestResolution,
        belowLayer ceiling: Int = Int(kCGMainMenuWindowLevel)
    ) async -> CGImage? {
        let windowIDs = await Self.windowsBelowMenuBar(intersecting: cgRect, belowLayer: ceiling).map(\.id)
        return await ScreenCapture.compositeWindows(windowIDs, in: cgRect, options: resolution)
    }

    @concurrent
    static nonisolated func windowsBelowMenuBar(
        intersecting cgRect: CGRect,
        belowLayer ceiling: Int = Int(kCGMainMenuWindowLevel)
    ) async -> [(id: CGWindowID, bounds: CGRect)] {
        WindowInfo.createWindows(option: .onScreen)
            .filter { $0.isOnScreen && $0.layer < ceiling && $0.bounds.intersects(cgRect) }
            .map { ($0.windowID, $0.bounds) }
    }
}
