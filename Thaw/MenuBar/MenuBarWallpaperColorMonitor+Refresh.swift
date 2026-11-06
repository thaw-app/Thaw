//
//  MenuBarWallpaperColorMonitor+Refresh.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

extension MenuBarWallpaperColorMonitor {
    /// The adaptive poll's cadence; the palette fallback derives from it rather than running its own timer.
    static let adaptiveRefreshInterval: TimeInterval = 30
    static let adaptiveRefreshTolerance: TimeInterval = 5

    /// The shortest gap between two adaptive polls, so each poll finds the palette due however often strips are sampled.
    static let paletteFallbackInterval: Duration = .seconds(adaptiveRefreshInterval - adaptiveRefreshTolerance)

    /// Average tint uses the bar strip; gradient tint also needs a full-height wallpaper palette.
    /// Track both so observers detect adaptive-kind changes and retries know when capture is complete.
    nonisolated struct AdaptiveCaptureRequirements: Equatable {
        /// Whether the average color of the menu bar strip is needed.
        let needsAverageColor: Bool

        /// Whether a palette of the wallpaper's dominant colors is needed.
        let needsPalette: Bool

        /// Whether the configuration samples the wallpaper at all.
        var isAdaptive: Bool {
            needsAverageColor || needsPalette
        }

        init(configuration: MenuBarAppearancePartialConfiguration, thawBarConfiguration: MenuBarAppearancePartialConfiguration? = nil) {
            let configurations = [configuration] + (thawBarConfiguration.map { [$0] } ?? [])
            needsAverageColor = configurations.contains { $0.backgroundKind == .adaptive || $0.tintKind.isAdaptive }
            needsPalette = configurations.contains { $0.tintKind == .adaptiveGradient }
        }
    }

    /// A palette with the inputs it was captured from.
    struct PaletteCapture {
        let palette: WallpaperPalette
        let state: PaletteRefreshState
    }

    struct PaletteRefreshState {
        let source: WallpaperPaletteRefreshPolicy.Source
        let refreshedAt: ContinuousClock.Instant
    }

    nonisolated enum AdaptiveRefreshAction: Equatable {
        /// Sampling requirements did not change.
        case unchanged

        /// Start the refresh: capture, then poll and watch the wallpaper.
        case start

        /// Capture changed requirements without restarting the running refresh.
        case recapture

        case stop
    }

    static nonisolated func adaptiveRefreshAction(
        from previous: AdaptiveCaptureRequirements?,
        to current: AdaptiveCaptureRequirements
    ) -> AdaptiveRefreshAction {
        guard previous != current else { return .unchanged }
        guard current.isAdaptive else {
            // Stop even on the first configuration so an earlier observer's refresh cannot outlive it.
            return .stop
        }
        return previous?.isAdaptive == true ? .recapture : .start
    }
}
