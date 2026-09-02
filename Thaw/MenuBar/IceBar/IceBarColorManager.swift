//
//  IceBarColorManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation
import SwiftUI

/// Live-samples the menu bar / wallpaper strip under the Thaw Bar so Match
/// Menu Bar can track desktop tone as the wallpaper, Space, or theme changes.
///
/// Sampling is not a fixed color: ``colorInfo`` is rewritten on show, on
/// frame moves, on space / display / appearance notifications, and on a short
/// periodic timer while the panel is visible.
@MainActor
@Observable
final class IceBarColorManager {
    private(set) var colorInfo: MenuBarAverageColorInfo?

    @ObservationIgnored
    private weak var iceBarPanel: IceBarPanel?

    @ObservationIgnored
    private var windowImage: CGImage?

    /// Monotonically incremented by updateWindowImage and clearWindowImage.
    /// A capture in flight stamps the value it observed; on completion it only
    /// writes windowImage if the value still matches, so a late completion
    /// can't undo a freshly cleared image or overwrite a newer capture.
    @ObservationIgnored
    private var windowImageGeneration: Int = 0

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Cancellable for the periodic refresh timer, active only while the Thaw Bar is visible.
    @ObservationIgnored
    private var periodicRefreshCancellable: AnyCancellable?

    func performSetup(with iceBarPanel: IceBarPanel) {
        self.iceBarPanel = iceBarPanel
        configureCancellables()
    }

    private func configureCancellables() {
        stopPeriodicRefresh()
        var c = Set<AnyCancellable>()

        if let iceBarPanel {
            iceBarPanel.publisher(for: \.screen)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] screen in
                    guard let self, let screen else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        _ = await self.updateWindowImage(for: screen)
                    }
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.frame)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self, weak iceBarPanel] frame in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        iceBarPanel.isVisible
                    else {
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

            // Notification-driven updates (space change, screen params, theme change).
            Publishers.Merge3(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                    .replace(with: ()),
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ()),
                DistributedNotificationCenter.default()
                    .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                    .replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak iceBarPanel] in
                guard let self else { return }
                // Clear window image on display changes to prevent memory growth
                // and invalidate any in-flight capture from before the change.
                self.clearWindowImage()
                guard
                    let iceBarPanel,
                    iceBarPanel.isVisible,
                    let screen = iceBarPanel.screen
                else {
                    return
                }
                let frame = iceBarPanel.frame
                Task { [weak self] in
                    guard let self else { return }
                    guard await self.updateWindowImage(for: screen) else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
            }
            .store(in: &c)

            // Manage visibility: update colors immediately + start/stop periodic timer.
            iceBarPanel.publisher(for: \.isVisible)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak iceBarPanel] isVisible in
                    guard let self else { return }
                    if isVisible {
                        if let iceBarPanel, let screen = iceBarPanel.screen {
                            let frame = iceBarPanel.frame
                            Task { [weak self] in
                                guard let self else { return }
                                guard await self.updateWindowImage(for: screen) else { return }
                                self.updateColorInfo(with: frame, screen: screen)
                            }
                        }
                        self.startPeriodicRefresh(for: iceBarPanel)
                    } else {
                        self.stopPeriodicRefresh()
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Starts a short periodic refresh so wallpaper / desktop tone changes
    /// propagate into Match Menu Bar without waiting for a Space switch.
    private func startPeriodicRefresh(for iceBarPanel: IceBarPanel?) {
        stopPeriodicRefresh()
        periodicRefreshCancellable = Timer.publish(every: 1.5, tolerance: 0.4, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self, weak iceBarPanel] _ in
                guard
                    let self,
                    let iceBarPanel,
                    iceBarPanel.isVisible,
                    let screen = iceBarPanel.screen
                else {
                    return
                }
                let frame = iceBarPanel.frame
                Task { [weak self] in
                    guard let self else { return }
                    guard await self.updateWindowImage(for: screen) else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
            }
    }

    /// Stops the periodic refresh timer.
    private func stopPeriodicRefresh() {
        periodicRefreshCancellable?.cancel()
        periodicRefreshCancellable = nil
        // Clear the window image to free memory when IceBar is hidden.
        clearWindowImage()
    }

    /// Clears windowImage and invalidates any in-flight capture. Use whenever
    /// callers want a synchronous nil state that an outstanding async capture
    /// must not be allowed to overwrite.
    private func clearWindowImage() {
        windowImageGeneration += 1
        windowImage = nil
    }

    /// Captures the menu bar / wallpaper strip for `screen`.
    ///
    /// - Returns: `true` when this call stored the current generation's image.
    ///   Callers must not update ``colorInfo`` after a `false` result — a stale
    ///   capture would otherwise sample a newer `windowImage` with an older
    ///   frame / screen.
    @discardableResult
    private func updateWindowImage(for screen: NSScreen) async -> Bool {
        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return false
        }

        let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
        // Quartz window bounds use a top-left origin. Capture the menu bar
        // window's own frame so the average matches the visible bar, not a
        // single pixel row or the bottom of the display.
        let bounds = menuBarWindow.bounds

        // Stamp our generation before suspending. If the counter advances while
        // we await (a clearWindowImage, a stopPeriodicRefresh, or a newer
        // updateWindowImage call), our completion is stale and must skip the
        // write so we don't undo intentional clears or clobber a fresher image.
        windowImageGeneration += 1
        let generation = windowImageGeneration

        let image = await ScreenCapture.captureWindowsAsync(
            with: windowIDs,
            screenBounds: bounds,
            option: .nominalResolution
        )
        guard generation == windowImageGeneration, let image else { return false }
        windowImage = image
        return true
    }

    /// The horizontal position (`0...1`) of the bar's center within the screen,
    /// used to sample the wallpaper/menu-bar color at the matching offset.
    ///
    /// `insetScreenFrame` is the screen inset by half the bar width on each
    /// side, so its width collapses to zero when a horizontal bar overflows to
    /// the full screen width — a state the bar itself detects at
    /// `frame.width == screen.frame.width` (see `IceBar.swift`). Dividing by
    /// that zero width yields `NaN`, which then drives `cropRect.x` and makes
    /// the color sample at a garbage offset (or stop updating) instead of the
    /// bar's actual center. The guard falls back to the panel's middle so the
    /// degenerate case still samples a sensible color.
    static func colorSamplePercentage(frame: CGRect, screenFrame: CGRect) -> CGFloat {
        let insetScreenFrame = screenFrame.insetBy(dx: frame.width / 2, dy: 0)
        guard insetScreenFrame.width > 0 else {
            return 0.5
        }
        return ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0 ... 1)
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let percentage = Self.colorSamplePercentage(frame: frame, screenFrame: screen.frame)

        // Sample a horizontal band across the full captured menu-bar height so
        // the average tracks the visible bar body, not only the top pixel row.
        let cropRect = CGRect(
            x: imageBounds.width * percentage,
            y: 0,
            width: 0,
            height: imageBounds.height
        )
        .insetBy(dx: -150, dy: 0)
        .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            // ignoreAlpha matches MenuBarManager's adaptive capture so
            // transparent composites don't pull the average toward black.
            let averageColor = croppedImage.averageColor(option: .ignoreAlpha)
        else {
            return
        }

        let next = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
        guard colorInfo != next else { return }
        colorInfo = next
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        // Keep the public signature synchronous so IceBar.show doesn't ripple
        // async upstream. Wraps the async refresh+color combo in a Task so
        // updateColorInfo reads the fresh capture instead of the previous
        // cycle's leftover.
        Task { [weak self] in
            guard let self else { return }
            await self.refresh(with: frame, screen: screen)
        }
    }

    /// Drops the standing sample so a cross-display Thaw Bar open cannot
    /// briefly reuse the previous screen's brightness for icon contrast.
    func invalidateColorInfo() {
        colorInfo = nil
        clearWindowImage()
    }

    /// Captures the menu bar strip for `screen` and rewrites ``colorInfo``.
    func refresh(with frame: CGRect, screen: NSScreen) async {
        guard await updateWindowImage(for: screen) else { return }
        updateColorInfo(with: frame, screen: screen)
    }
}
