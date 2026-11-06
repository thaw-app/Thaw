//
//  MenuBarWallpaperColorMonitor+Capture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawCapture

extension MenuBarWallpaperColorMonitor {
    /// Adaptive backgrounds and tints need continuing color samples.
    var isAdaptiveAppearanceActive: Bool {
        adaptiveCaptureRequirements?.isAdaptive ?? false
    }

    /// Sample only for visible capture UI; closed surfaces retain cached colors.
    var adaptiveCaptureRequirements: AdaptiveCaptureRequirements? {
        guard let appState, appState.navigationState.hasVisibleCaptureUI else {
            return nil
        }
        return AdaptiveCaptureRequirements(
            configuration: appState.appearanceManager.configuration.current,
            thawBarConfiguration: appState.navigationState.isThawBarPresented || settingsWindow?.isVisible == true
                ? appState.appearanceManager.configuration.resolvedThawBarAppearance.fillConfiguration : nil
        )
    }

    /// Fire-and-forget refresh; callers needing fresh state immediately must await updateAverageColorInfoAsync.
    func updateAverageColorInfo() {
        Task { [weak self] in
            await self?.updateAverageColorInfoAsync()
        }
    }

    /// Awaitable refresh; color writes finish on MainActor before returning.
    func updateAverageColorInfoAsync(for requestedDisplayID: CGDirectDisplayID? = nil) async {
        guard let appState, appState.navigationState.hasVisibleCaptureUI else { return }

        let requirements = adaptiveCaptureRequirements
        guard let targetScreens = captureTargetScreens(
            requestedDisplayID: requestedDisplayID,
            isAdaptiveActive: requirements?.isAdaptive ?? false
        ), !targetScreens.isEmpty else { return }

        let windows = WindowInfo.createWindows(option: .onScreen)
        let activeDisplayID = NSScreen.screenWithActiveMenuBar?.displayID

        let needsPalette = requirements?.needsPalette ?? false

        // Prevent slow captures from overwriting newer colors.
        captureGeneration += 1
        let generation = captureGeneration

        // Capture serially so a newer generation can take over between displays.
        for screen in targetScreens {
            let displayID = screen.displayID
            // Stop if a newer pass has taken over.
            guard captureGeneration == generation else { break }
            guard let result = await captureAverageColor(
                for: displayID,
                from: windows,
                needsPalette: needsPalette
            )
            else {
                continue
            }
            // Recheck after suspension before publishing over a newer pass.
            guard captureGeneration == generation else { break }
            let (_, info, paletteCapture) = result
            publish(info, for: displayID, isActiveDisplay: displayID == activeDisplayID)
            if let paletteCapture {
                publish(paletteCapture, for: displayID)
            }
        }
    }

    /// The requested display, every screen while adaptive, the settings window's screen, or the active bar's; nil skips the pass.
    private func captureTargetScreens(requestedDisplayID: CGDirectDisplayID?, isAdaptiveActive: Bool) -> [NSScreen]? {
        if let requestedDisplayID {
            guard let screen = NSScreen.screen(for: requestedDisplayID) else { return nil }
            return [screen]
        } else if isAdaptiveActive {
            return NSScreen.managedScreens
        } else if settingsWindow?.isVisible == true {
            return [settingsWindow?.screen].compactMap(\.self)
        } else {
            guard let screen = NSScreen.screenWithActiveMenuBar else { return nil }
            return [screen]
        }
    }

    /// Each sample holds a capture ticket because this sampler can run without a surface opening the ordinary gate.
    private func captureAverageColor(
        for displayID: CGDirectDisplayID,
        from windows: [WindowInfo],
        needsPalette: Bool
    ) async -> (CGDirectDisplayID, MenuBarAverageColorInfo, PaletteCapture?)? {
        guard let sample = await ScreenCapture.withOneshotCaptureTicket({
                  await MenuBarColorSampler.captureStrip(for: displayID, from: windows)
              }),
              let color = sample.image.averageColor(option: .ignoreAlpha)
        else {
            return nil
        }
        var paletteCapture: PaletteCapture?
        if needsPalette {
            paletteCapture = await capturePaletteIfStale(for: displayID, sample: sample, stripColor: color)
        }
        return (displayID, MenuBarAverageColorInfo(color: color, source: .menuBarWindow), paletteCapture)
    }

    /// Strip samples arrive every few seconds; the full-wallpaper capture runs only when the policy finds the palette stale.
    private func capturePaletteIfStale(
        for displayID: CGDirectDisplayID,
        sample: MenuBarColorSampler.Sample,
        stripColor: CGColor
    ) async -> PaletteCapture? {
        let source = WallpaperPaletteRefreshPolicy.Source(
            wallpaperGeneration: wallpaperGeneration,
            stripColor: stripColor,
            wallpaperBounds: sample.wallpaperBounds,
            isDarkAppearance: SystemAppearance.current == .dark
        )
        let now = ContinuousClock.now
        // A display without a usable palette has nothing to reuse, whatever was recorded for it.
        let state = wallpaperPalettes[displayID]?.primary == nil ? nil : paletteRefreshStates[displayID]
        let reason = WallpaperPaletteRefreshPolicy.refreshReason(
            previous: state?.source,
            current: source,
            timeSinceLastRefresh: state.map { now - $0.refreshedAt },
            fallbackInterval: Self.paletteFallbackInterval
        )
        guard let reason else { return nil }
        diagLog.debug("Refreshing wallpaper palette for display \(displayID): \(reason)")

        // The one-pixel strip suffices for averaging, but a palette needs the wallpaper's full height.
        let palette = await ScreenCapture.withOneshotCaptureTicket {
            await ScreenCapture.captureWindows(
                with: sample.windowIDs,
                screenBounds: sample.wallpaperBounds,
                option: .nominalResolution
            )
        }?.dominantColors()
        // Retain the previous palette on misses or empty swatches to avoid losing tint or falling back to average color.
        guard let palette, palette.primary != nil else { return nil }
        return PaletteCapture(palette: palette, state: PaletteRefreshState(source: source, refreshedAt: now))
    }

    /// Retry early WindowServer capture failures until all screens have the required samples or the budget expires.
    func captureAdaptiveColorWithRetry() {
        // Await capture to avoid spending retries on stale reads.
        Task { [weak self] in
            guard let self else { return }
            for attempt in 0 ..< 10 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(1))
                }
                await self.updateAverageColorInfoAsync()
                if self.hasCompleteAdaptiveCapture() {
                    return
                }
            }
        }
    }

    /// Palette capture can fail while the strip succeeds; require both when needed so retries do not stop on the fallback.
    private func hasCompleteAdaptiveCapture() -> Bool {
        // No capture requirements means further retries would only spin.
        guard let requirements = adaptiveCaptureRequirements else { return true }
        return NSScreen.managedScreens.allSatisfy { screen in
            let displayID = screen.displayID
            guard averageColors.keys.contains(displayID) else { return false }
            return !requirements.needsPalette || wallpaperPalettes[displayID]?.primary != nil
        }
    }
}
