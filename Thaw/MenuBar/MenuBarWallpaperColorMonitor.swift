//
//  MenuBarWallpaperColorMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation
import ThawCapture

/// Samples the bar's average colour and the wallpaper palette for adaptive backgrounds, tints and the settings preview.
/// Keeps the samples current across Space, display, wallpaper and sleep changes.
@MainActor
@Observable
final class MenuBarWallpaperColorMonitor {
    /// Information for the menu bar's average color on the active screen.
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Per-screen average colors for multi-monitor adaptive backgrounds.
    private(set) var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] = [:]

    /// Per-screen dominant-color palettes for the adaptive gradient tint.
    private(set) var wallpaperPalettes: [CGDirectDisplayID: WallpaperPalette] = [:]

    /// Track visibility to sample live colors only while settings needs them.
    private(set) var settingsWindow: NSWindow?

    @ObservationIgnored
    let diagLog = DiagLog(category: "MenuBarManager")

    /// Weak because AppState owns the menu bar manager that holds this monitor.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Cancellable for the periodic average-color refresh, active only while settings is visible.
    @ObservationIgnored
    private var averageColorRefreshCancellable: AnyCancellable?

    /// Re-subscribe to isVisible KVO for each new non-nil settings window.
    @ObservationIgnored
    private var settingsWindowVisibilityCancellable: AnyCancellable?

    /// Cancellable for the periodic average-color refresh when adaptive background is active.
    @ObservationIgnored
    private var adaptiveColorRefreshCancellable: AnyCancellable?

    /// Wallpaper changes retint immediately rather than waiting for a poll.
    @ObservationIgnored
    private let wallpaperChangeMonitor = WallpaperChangeMonitor()

    /// Advances when the wallpaper may have been replaced; palettes captured under an older value are stale.
    @ObservationIgnored
    private(set) var wallpaperGeneration = 0

    /// What each published palette was captured from and when, keyed by display.
    @ObservationIgnored
    private(set) var paletteRefreshStates: [CGDirectDisplayID: PaletteRefreshState] = [:]

    /// Generation checks prevent slow captures from overwriting newer samples or wake-restored colors.
    @ObservationIgnored
    var captureGeneration = 0

    /// Per-screen colors cached before sleep, restored on wake to avoid stale/white flash.
    @ObservationIgnored
    private var sleepColorCache: [CGDirectDisplayID: MenuBarAverageColorInfo]?

    /// Skip sampling sleeping displays: captures cost work and do not reflect the wallpaper.
    @ObservationIgnored
    private var displaysAreAsleep = false

    /// Polling state for adaptive wake stabilization.
    @ObservationIgnored
    private var wakePollTimer: AnyCancellable?
    private var wakePollPrevColors: [CGDirectDisplayID: MenuBarAverageColorInfo]?
    private var wakePollStableCount = 0
    private var wakePollDidChange = false
    private var wakePollStartTime: ContinuousClock.Instant?

    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    // MARK: - Observers

    /// Stops the settings preview poll before the menu bar manager rebuilds its observers.
    func stopSettingsPreviewRefresh() {
        averageColorRefreshCancellable?.cancel()
        averageColorRefreshCancellable = nil
    }

    func observeSettingsWindowReference(into bag: inout Set<AnyCancellable>) {
        appState?.windowPublisher(for: .settings)
            .sink { [weak self] window in
                self?.settingsWindow = window
            }
            .store(in: &bag)
    }

    /// Installs the settings preview, Space and display, sleep and adaptive appearance observers, in that order.
    func observeSamplingTriggers(into bag: inout Set<AnyCancellable>) {
        observeSettingsWindowVisibility(into: &bag)
        observeEnvironmentChanges(into: &bag)
        observeDisplaySleepCycle(into: &bag)
        observeAdaptiveAppearance(into: &bag)
    }

    /// Poll colors while settings previews them because macOS posts no desktop-picture notification.
    /// Stop sampling and the timer when the window is dismissed.
    private func observeSettingsWindowVisibility(into bag: inout Set<AnyCancellable>) {
        // Observe the window reference, then re-subscribe to its separate isVisible KVO stream for each non-nil window.
        let task = Task { @MainActor [weak self] in
            let changes = Observations { self?.settingsWindow }
            for await window in changes {
                guard let self else { return }
                guard let window else {
                    // KVO retains the window; drop the subscription to release the closed window and its views.
                    settingsWindowVisibilityCancellable = nil
                    averageColorRefreshCancellable?.cancel()
                    averageColorRefreshCancellable = nil
                    continue
                }
                subscribeToSettingsWindowVisibility(of: window)
            }
        }
        AnyCancellable { task.cancel() }
            .store(in: &bag)
    }

    private func subscribeToSettingsWindowVisibility(of window: NSWindow) {
        settingsWindowVisibilityCancellable = window.publisher(for: \.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else { return }
                guard isVisible else {
                    averageColorRefreshCancellable?.cancel()
                    averageColorRefreshCancellable = nil
                    return
                }
                updateAverageColorInfo()
                averageColorRefreshCancellable = Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self, !displaysAreAsleep else { return }
                        updateAverageColorInfo()
                    }
            }
    }

    /// Space and display changes can replace the wallpaper; resample only with an active consumer.
    private func observeEnvironmentChanges(into bag: inout Set<AnyCancellable>) {
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .replace(with: ()),
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .replace(with: ())
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            // Count it even with no consumer, so a palette kept from before is not reused later.
            wallpaperGeneration += 1
            guard settingsWindow?.isVisible == true || isAdaptiveAppearanceActive else {
                return
            }
            updateAverageColorInfo()
        }
        .store(in: &bag)
    }

    /// Restore banked colors immediately on wake to avoid a white flash, then poll for changed, settled samples.
    /// Screen sleep/wake notifications cover both display-only sleep and system sleep.
    private func observeDisplaySleepCycle(into bag: inout Set<AnyCancellable>) {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                displaysAreAsleep = true
                sleepColorCache = averageColors
            }
            .store(in: &bag)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                displaysAreAsleep = false
                restoreColorsAfterWake()
            }
            .store(in: &bag)
    }

    /// Refresh without stabilization polling if no pre-sleep colors were banked.
    private func restoreColorsAfterWake() {
        guard isAdaptiveAppearanceActive else {
            return
        }
        guard let cache = sleepColorCache else {
            updateAverageColorInfo()
            return
        }

        // Invalidate pre-sleep captures so they cannot overwrite the restored colors.
        captureGeneration += 1
        averageColors = cache
        if
            let displayID = NSScreen.screenWithActiveMenuBar?.displayID,
            let cached = cache[displayID]
        {
            averageColorInfo = cached
        }

        wakePollPrevColors = nil
        wakePollStableCount = 0
        wakePollDidChange = false
        wakePollStartTime = .now
        wakePollTimer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.advanceWakeStabilizationPoll()
                }
            }
    }

    /// Await capture so comparisons use this tick's colors rather than exhausting the poll budget on stale values.
    /// Dropping wakePollTimer ends polling and releases the subscription.
    private func advanceWakeStabilizationPoll() async {
        let elapsed = wakePollStartTime.map { $0.duration(to: .now) } ?? .zero
        if elapsed >= .seconds(10) {
            endWakeStabilizationPoll()
            return
        }

        await updateAverageColorInfoAsync()
        let sampled = averageColors

        if !wakePollDidChange, let cache = sleepColorCache, sampled != cache {
            wakePollDidChange = true
        }

        if wakePollDidChange {
            if let previous = wakePollPrevColors, previous == sampled {
                wakePollStableCount += 1
                if wakePollStableCount >= 1 {
                    endWakeStabilizationPoll()
                    return
                }
            } else {
                wakePollStableCount = 0
            }
        }

        wakePollPrevColors = sampled
    }

    private func endWakeStabilizationPoll() {
        sleepColorCache = nil
        wakePollTimer = nil
    }

    /// Retry initial adaptive capture while WindowServer settles at launch; later polling is slow to catch gradual changes.
    private func observeAdaptiveAppearance(into bag: inout Set<AnyCancellable>) {
        guard appState != nil else {
            return
        }
        // Deduplicate derived capture requirements across Observation updates.
        let task = Task { @MainActor [weak self] in
            let changes = Observations { [weak self] in
                self?.adaptiveCaptureRequirements ?? AdaptiveCaptureRequirements(configuration: .defaultConfiguration)
            }
            var previous: AdaptiveCaptureRequirements?
            for await requirements in changes {
                guard let self else { return }
                let action = Self.adaptiveRefreshAction(from: previous, to: requirements)
                previous = requirements
                switch action {
                case .unchanged:
                    continue
                case .recapture:
                    // Gradient tint needs a new palette now; waiting for the poll would leave the average-color fallback.
                    captureAdaptiveColorWithRetry()
                case .start:
                    captureAdaptiveColorWithRetry()
                    adaptiveColorRefreshCancellable = Timer.publish(
                        every: Self.adaptiveRefreshInterval,
                        tolerance: Self.adaptiveRefreshTolerance,
                        on: .main,
                        in: .default
                    )
                    .autoconnect()
                    .sink { [weak self] _ in
                        // Skip sleep ticks; wake restores banked colors and runs its own poll.
                        guard let self, !displaysAreAsleep else { return }
                        updateAverageColorInfo()
                    }
                    wallpaperChangeMonitor.onChange = { [weak self] in
                        self?.wallpaperGeneration += 1
                        self?.captureAdaptiveColorWithRetry()
                    }
                    wallpaperChangeMonitor.start()
                case .stop:
                    adaptiveColorRefreshCancellable?.cancel()
                    adaptiveColorRefreshCancellable = nil
                    wallpaperChangeMonitor.stop()
                }
            }
        }
        AnyCancellable { task.cancel() }
            .store(in: &bag)
    }

    /// Publishes one display's sample, writing only values that changed so observers do not repaint.
    func publish(_ info: MenuBarAverageColorInfo, for displayID: CGDirectDisplayID, isActiveDisplay: Bool) {
        if averageColors[displayID] != info {
            averageColors[displayID] = info
        }
        if isActiveDisplay, averageColorInfo != info {
            averageColorInfo = info
        }
    }

    /// Record the inputs only with the palette they produced, so a superseded pass cannot mark a stale palette fresh.
    func publish(_ capture: PaletteCapture, for displayID: CGDirectDisplayID) {
        if wallpaperPalettes[displayID] != capture.palette {
            wallpaperPalettes[displayID] = capture.palette
        }
        paletteRefreshStates[displayID] = capture.state
    }
}
