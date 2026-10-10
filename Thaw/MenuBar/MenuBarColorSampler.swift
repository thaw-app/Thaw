//
//  MenuBarColorSampler.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import MenuBarModel
import ThawCapture

/// One implementation of the menu bar strip sample shared by the menu bar
/// colour cycle, the search panel and the Thaw Bar.
nonisolated enum MenuBarColorSampler {
    /// A captured strip and the windows it came from.
    struct Sample: Sendable {
        /// The one-pixel strip: the wallpaper with the menu bar composited
        /// over it.
        let image: CGImage

        /// The captured windows, in front-to-back order, for callers that need
        /// a second capture at the wallpaper's real height.
        let windowIDs: [CGWindowID]

        /// The wallpaper window's full bounds.
        let wallpaperBounds: CGRect
    }

    /// Captures the strip behind displayID's menu bar.
    ///
    /// The strip is the wallpaper window with the menu bar backdrop composited
    /// over it, one pixel tall, which is all an average needs. The caller owns
    /// the capture ticket: the menu bar's own sampling cycle runs with no Thaw
    /// surface open and wraps this in ScreenCapture.withOneshotCaptureTicket(_:),
    /// while the search panel and Thaw Bar sample with their own capture UI
    /// already active.
    static func captureStrip(
        for displayID: CGDirectDisplayID,
        from windows: [WindowInfo]
    ) async -> Sample? {
        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return nil
        }
        let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
        var stripBounds = wallpaperWindow.bounds
        stripBounds.size.height = 1
        guard let image = await ScreenCapture.captureWindows(
            with: windowIDs,
            screenBounds: stripBounds,
            option: .nominalResolution
        ) else {
            return nil
        }
        return Sample(image: image, windowIDs: windowIDs, wallpaperBounds: wallpaperWindow.bounds)
    }
}
