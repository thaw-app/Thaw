//
//  IceBarColorManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

@MainActor
final class IceBarColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceBarPanel: IceBarPanel?

    private var windowImage: CGImage?

    /// Monotonically incremented by updateWindowImage and clearWindowImage.
    /// A capture in flight stamps the value it observed; on completion it only
    /// writes windowImage if the value still matches, so a late completion
    /// can't undo a freshly cleared image or overwrite a newer capture.
    private var windowImageGeneration: Int = 0

    private var cancellables = Set<AnyCancellable>()

    /// Cancellable for the periodic refresh timer, active only while the Thaw Bar is visible.
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
                    guard
                        let self,
                        let screen,
                        screen == .main
                    else {
                        return
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        await self.updateWindowImage(for: screen)
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
                        iceBarPanel.isVisible,
                        screen == .main
                    else {
                        return
                    }
                    withAnimation(.interactiveSpring) {
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
                guard let self else {
                    return
                }
                // Clear window image on display changes to prevent memory growth
                // and invalidate any in-flight capture from before the change.
                self.clearWindowImage()
                guard
                    let iceBarPanel,
                    iceBarPanel.isVisible,
                    let screen = iceBarPanel.screen,
                    screen == .main
                else {
                    return
                }
                let frame = iceBarPanel.frame
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateWindowImage(for: screen)
                    withAnimation {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
            }
            .store(in: &c)

            // Manage visibility: update colors immediately + start/stop periodic timer.
            // Single subscription replaces the previous two \.isVisible observers.
            iceBarPanel.publisher(for: \.isVisible)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak iceBarPanel] isVisible in
                    guard let self else { return }
                    if isVisible {
                        // Refresh windowImage immediately so the first color
                        // update isn't stale. Awaiting inside a Task so
                        // updateColorInfo reads the fresh capture, not the
                        // previous cycle's leftover.
                        if let iceBarPanel, let screen = iceBarPanel.screen, screen == .main {
                            let frame = iceBarPanel.frame
                            Task { [weak self] in
                                guard let self else { return }
                                await self.updateWindowImage(for: screen)
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

    /// Starts the 5-second periodic refresh timer for color updates.
    private func startPeriodicRefresh(for iceBarPanel: IceBarPanel?) {
        stopPeriodicRefresh()
        periodicRefreshCancellable = Timer.publish(every: 5, tolerance: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self, weak iceBarPanel] _ in
                guard
                    let self,
                    let iceBarPanel,
                    iceBarPanel.isVisible,
                    let screen = iceBarPanel.screen,
                    screen == .main
                else {
                    return
                }
                let frame = iceBarPanel.frame
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateWindowImage(for: screen)
                    withAnimation {
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

    private func updateWindowImage(for screen: NSScreen) async {
        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
        let bounds = withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 }

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
        guard generation == windowImageGeneration, let image else { return }
        windowImage = image
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0 ... 1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether its image contributed to the average.
        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        // Keep the public signature synchronous so IceBar.show doesn't ripple
        // async upstream. Wraps the async refresh+color combo in a Task so
        // updateColorInfo reads the fresh capture instead of the previous
        // cycle's leftover.
        Task { [weak self] in
            guard let self else { return }
            await self.updateWindowImage(for: screen)
            self.updateColorInfo(with: frame, screen: screen)
        }
    }
}
