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

/// Samples the menu bar / wallpaper strip under the Thaw Bar for icon contrast.
///
/// Samples whichever screen the panel is on, not just the main display.
@MainActor
@Observable
final class IceBarColorManager {
    private(set) var colorInfo: MenuBarAverageColorInfo?

    @ObservationIgnored
    private weak var iceBarPanel: IceBarPanel?

    @ObservationIgnored
    private var windowImage: CGImage?

    /// A capture only writes windowImage if this hasn't moved since it
    /// started, so a late completion can't undo a clear or a newer capture.
    @ObservationIgnored
    private var windowImageGeneration: Int = 0

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Active only while the Thaw Bar is visible.
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
                .sink { [weak self, weak iceBarPanel] screen in
                    guard let self, let screen, let iceBarPanel, iceBarPanel.isVisible else {
                        return
                    }
                    // Drop the previous display's sample before the new capture
                    // lands so icon contrast cannot briefly reuse the old screen.
                    self.invalidateColorInfo()
                    let frame = iceBarPanel.frame
                    Task { [weak self] in
                        guard let self else { return }
                        await self.refresh(with: frame, screen: screen)
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
                    withAnimation(.interactiveSpring) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

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
                guard let self else {
                    return
                }
                // Also invalidates any in-flight capture.
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
                    withAnimation {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
            }
            .store(in: &c)

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

    private func startPeriodicRefresh(for iceBarPanel: IceBarPanel?) {
        stopPeriodicRefresh()
        periodicRefreshCancellable = Timer.publish(every: 5, tolerance: 1, on: .main, in: .default)
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
                    withAnimation {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
            }
    }

    private func stopPeriodicRefresh() {
        periodicRefreshCancellable?.cancel()
        periodicRefreshCancellable = nil
        clearWindowImage()
    }

    /// Clears windowImage and invalidates any in-flight capture.
    private func clearWindowImage() {
        windowImageGeneration += 1
        windowImage = nil
    }

    /// Captures the menu bar / wallpaper strip for `screen`.
    ///
    /// - Returns: `true` when this call stored the current generation's image.
    ///   Don't update ``colorInfo`` after `false`.
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
        // window's own frame so the average matches the visible bar body.
        let bounds = menuBarWindow.bounds

        // Stamp before suspending; skip the write if it moved meanwhile.
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

    /// The horizontal position (`0...1`) of the bar's center within the screen.
    ///
    /// A full-width bar collapses the inset frame to zero width, so the guard
    /// falls back to the middle instead of dividing into `NaN`.
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

        // Full height, not only the top pixel row.
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
            let averageColor = croppedImage.averageColor(option: .ignoreAlpha)
        else {
            return
        }

        let next = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
        guard colorInfo != next else { return }
        colorInfo = next
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        // Synchronous so IceBar.show doesn't go async.
        Task { [weak self] in
            guard let self else { return }
            await self.refresh(with: frame, screen: screen)
        }
    }

    /// So a cross-display open can't reuse the previous screen's brightness.
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
