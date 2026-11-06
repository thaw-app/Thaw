//
//  WallpaperPaletteRefreshPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// When a strip sample may reuse the published palette instead of capturing the wallpaper again.
/// The capture needs a window server, so only the decision in front of it is pinned here.
@Suite("Wallpaper palette refresh policy")
struct WallpaperPaletteRefreshPolicyTests {
    private typealias Policy = WallpaperPaletteRefreshPolicy

    private static let fallbackInterval: Duration = .seconds(25)

    private func source(
        wallpaperGeneration: Int = 3,
        stripColor: CGColor = CGColor(srgbRed: 0.29, green: 0.45, blue: 0.63, alpha: 1),
        wallpaperBounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
        isDarkAppearance: Bool = false
    ) -> Policy.Source {
        Policy.Source(
            wallpaperGeneration: wallpaperGeneration,
            stripColor: stripColor,
            wallpaperBounds: wallpaperBounds,
            isDarkAppearance: isDarkAppearance
        )
    }

    private func reason(
        previous: Policy.Source?,
        current: Policy.Source,
        after elapsed: Duration? = .seconds(5)
    ) -> Policy.Reason? {
        Policy.refreshReason(
            previous: previous,
            current: current,
            timeSinceLastRefresh: elapsed,
            fallbackInterval: Self.fallbackInterval
        )
    }

    @Test("An unchanged sample inside the fallback interval reuses the palette")
    func unchangedSampleReusesPalette() {
        #expect(reason(previous: source(), current: source()) == nil)
        #expect(reason(previous: source(), current: source(), after: .zero) == nil)
        #expect(reason(previous: source(), current: source(), after: .seconds(24.9)) == nil)
    }

    @Test("A display with no palette captures one")
    func missingPaletteRefreshes() {
        #expect(reason(previous: nil, current: source()) == .noPalette)
        #expect(reason(previous: nil, current: source(), after: nil) == .noPalette)
    }

    @Test("A wallpaper, Space or display-parameter change refreshes the palette")
    func wallpaperGenerationRefreshes() {
        #expect(reason(previous: source(), current: source(wallpaperGeneration: 4)) == .wallpaperChanged)
    }

    @Test("A strip that changed color refreshes the palette without any notification")
    func stripColorRefreshes() {
        let gray = CGColor(srgbRed: 0.76, green: 0.78, blue: 0.8, alpha: 1)

        #expect(reason(previous: source(), current: source(stripColor: gray)) == .wallpaperChanged)
    }

    @Test("A display whose wallpaper bounds moved or resized refreshes the palette")
    func displayChangeRefreshes() {
        let resized = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let moved = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

        #expect(reason(previous: source(), current: source(wallpaperBounds: resized)) == .displayChanged)
        #expect(reason(previous: source(), current: source(wallpaperBounds: moved)) == .displayChanged)
    }

    @Test("A light/dark switch refreshes the palette in either direction")
    func appearanceChangeRefreshes() {
        let light = source(isDarkAppearance: false)
        let dark = source(isDarkAppearance: true)

        #expect(reason(previous: light, current: dark) == .appearanceChanged)
        #expect(reason(previous: dark, current: light) == .appearanceChanged)
    }

    @Test("An unchanged sample refreshes once the fallback interval has elapsed")
    func fallbackIntervalRefreshes() {
        #expect(reason(previous: source(), current: source(), after: .seconds(25)) == .fallbackIntervalElapsed)
        #expect(reason(previous: source(), current: source(), after: .seconds(300)) == .fallbackIntervalElapsed)
        #expect(reason(previous: source(), current: source(), after: nil) == .fallbackIntervalElapsed)
    }

    @Test("Five-second strip samples reach the fallback only on the sixth")
    func stripCadenceSkipsPaletteCaptures() {
        let refreshes = stride(from: 5, through: 30, by: 5).filter { seconds in
            reason(previous: source(), current: source(), after: .seconds(seconds)) != nil
        }

        #expect(refreshes == [25, 30])
    }

    @MainActor
    @Test("Every adaptive poll finds the palette due, however early its tolerance lets it fire")
    func adaptivePollAlwaysRefreshes() {
        let earliestPollGap: Duration = .seconds(30 - 5)

        #expect(Policy.refreshReason(
            previous: source(),
            current: source(),
            timeSinceLastRefresh: earliestPollGap,
            fallbackInterval: MenuBarManager.paletteFallbackInterval
        ) == .fallbackIntervalElapsed)
    }
}
