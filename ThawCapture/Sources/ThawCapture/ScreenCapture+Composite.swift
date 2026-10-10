//
//  ScreenCapture+Composite.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

public extension ScreenCapture {
    /// Composites the given windows into one image of screenBounds.
    ///
    /// For callers that pick their own windows below the menu bar, such as the
    /// backdrop and wallpaper palette.
    @concurrent
    static nonisolated func compositeWindows(
        _ windowIDs: [CGWindowID],
        in screenBounds: CGRect,
        options: CGWindowImageOption
    ) async -> CGImage? {
        guard !windowIDs.isEmpty else { return nil }
        return Bridging.captureWindowsImage(windowIDs: windowIDs, screenBounds: screenBounds, options: options)
    }
}
