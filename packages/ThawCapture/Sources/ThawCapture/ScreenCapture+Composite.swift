//
//  ScreenCapture+Composite.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

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
        guard !windowIDs.isEmpty, !Task.isCancelled else { return nil }
        // Backdrops remain visible with no capture panel open. Never fall back
        // to SkyLight here: its per-call leak must stay in the helper.
        return await withOneshotCaptureTicket {
            await MenuBarCaptureServiceClient.shared.captureBackdrop(
                windowIDs: windowIDs,
                screenBounds: screenBounds,
                options: options
            )
        }
    }
}
