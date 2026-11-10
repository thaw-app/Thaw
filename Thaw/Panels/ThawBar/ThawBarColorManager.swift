//
//  ThawBarColorManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import Observation
import SwiftUI
import ThawCapture
import ThawUI

@MainActor
@Observable
final class ThawBarColorManager {
    private(set) var colorInfo: MenuBarAverageColorInfo?
    private(set) var colorDisplayID: CGDirectDisplayID?

    @ObservationIgnored
    private weak var thawBarPanel: ThawBarPanel?

    @ObservationIgnored
    private weak var appState: AppState?

    @ObservationIgnored
    private var windowImage: (displayID: CGDirectDisplayID, image: CGImage)?

    /// Monotonically incremented by updateWindowImage and clearWindowImage.
    /// A capture in flight stamps the value it observed; on completion it only
    /// writes windowImage if the value still matches, so a late completion
    /// can't undo a freshly cleared image or overwrite a newer capture.
    @ObservationIgnored
    private(set) var windowImageGeneration: Int = 0

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Cancellable for the periodic refresh timer, active only while the Thaw Bar is visible.
    @ObservationIgnored
    private var periodicRefreshCancellable: AnyCancellable?

    static func backgroundSample(
        for displayID: CGDirectDisplayID,
        overridesMenuBar: Bool,
        sharedSamples: [CGDirectDisplayID: MenuBarAverageColorInfo],
        localSample: MenuBarAverageColorInfo?
    ) -> MenuBarAverageColorInfo? {
        overridesMenuBar ? localSample : sharedSamples[displayID]
    }

    func performSetup(with thawBarPanel: ThawBarPanel, appState: AppState, displaySettlements: some Publisher<EnvironmentChange, Never>) {
        self.thawBarPanel = thawBarPanel
        self.appState = appState
        stopPeriodicRefresh()
        cancellables.removeAll()

        // A strip belongs to one display; never crop it with another display's frame.
        thawBarPanel.publisher(for: \.screen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                clearWindowImage()
                refreshWhilePresented(animated: false)
            }
            .store(in: &cancellables)

        // Moving the panel changes which slice of the strip sits behind it;
        // resampling the existing capture is enough, no re-capture needed.
        thawBarPanel.publisher(for: \.frame)
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self, weak thawBarPanel] frame in
                guard
                    let self, let thawBarPanel, let screen = thawBarPanel.screen, thawBarPanel.isVisible, self.appState?.appearanceManager.configuration.thawBarAppearance.overridesMenuBar == true
                else {
                    return
                }
                withThawAnimation(.interactiveSpring) {
                    self.updateColorInfo(with: frame, screen: screen)
                }
            }
            .store(in: &cancellables)

        let appearanceTask = Task { @MainActor [weak self, weak appState] in
            let changes = Observations { appState?.appearanceManager.configuration.thawBarAppearance.overridesMenuBar }
            for await _ in changes {
                guard let self else { return }
                clearWindowImage()
                refreshWhilePresented(animated: false)
            }
        }
        AnyCancellable { appearanceTask.cancel() }.store(in: &cancellables)

        // Space, settled display and theme changes all invalidate the strip.
        // Clear it first so a stale in-flight capture can't resurrect it, then
        // recapture if the panel is currently up.
        Publishers.Merge(
            DisplayEnvironment.spaceOrDisplayChanges(merging: displaySettlements.replace(with: ())),
            DistributedNotificationCenter.default()
                .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                .replace(with: ())
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            clearWindowImage()
            refreshWhilePresented(animated: true)
        }
        .store(in: &cancellables)

        // Showing the panel refreshes immediately (so the first color read is
        // not stale) and starts the periodic timer; hiding stops the timer
        // and drops the capture.
        thawBarPanel.publisher(for: \.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible {
                    refreshWhilePresented(animated: false)
                    startPeriodicRefresh()
                } else {
                    stopPeriodicRefresh()
                }
            }
            .store(in: &cancellables)
    }

    /// Hidden panels do not keep either sampling path active.
    private func refreshWhilePresented(animated: Bool) {
        guard
            let thawBarPanel, thawBarPanel.isVisible, let screen = thawBarPanel.screen
        else {
            return
        }
        captureThenPublish(frame: thawBarPanel.frame, screen: screen, animated: animated)
    }

    /// Recaptures the sample strip, then publishes the color read from it.
    ///
    /// The await keeps ordering: the color is read from the fresh capture,
    /// not the previous cycle's leftover.
    private func captureThenPublish(frame: CGRect, screen: NSScreen, animated: Bool) {
        Task { [weak self] in
            guard let self, let appState else { return }
            if !appState.appearanceManager.configuration.thawBarAppearance.overridesMenuBar {
                await appState.menuBarManager.updateAverageColorInfoAsync(for: screen.displayID)
                return
            }
            await updateWindowImage(for: screen)
            if animated {
                withThawAnimation(.default) {
                    self.updateColorInfo(with: frame, screen: screen)
                }
            } else {
                updateColorInfo(with: frame, screen: screen)
            }
        }
    }

    /// Starts the 5-second periodic refresh timer for color updates.
    private func startPeriodicRefresh() {
        stopPeriodicRefresh()
        periodicRefreshCancellable = Timer.publish(every: 5, tolerance: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshWhilePresented(animated: true)
            }
    }

    /// Stops the periodic refresh timer.
    private func stopPeriodicRefresh() {
        periodicRefreshCancellable?.cancel()
        periodicRefreshCancellable = nil
        // Clear the window image to free memory when ThawBar is hidden.
        clearWindowImage()
    }

    /// Drops observers, timers, and cached strip buffers when the panel tears down while idle.
    func tearDownIdle() {
        stopPeriodicRefresh()
        cancellables.removeAll()
        clearWindowImage()
        colorInfo = nil
        colorDisplayID = nil
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

        // Stamp our generation before suspending. If the counter advances while
        // we await (a clearWindowImage, a stopPeriodicRefresh, or a newer
        // updateWindowImage call), our completion is stale and must skip the
        // write so we don't undo intentional clears or clobber a fresher image.
        windowImageGeneration += 1
        let generation = windowImageGeneration

        let image = await MenuBarColorSampler.captureStrip(for: displayID, from: windows)?.image
        guard generation == windowImageGeneration, let image else { return }
        windowImage = (displayID, image)
    }

    /// Maps a panel frame in screen coordinates onto a proportionally scaled region of the captured strip.
    static nonisolated func sampleRect(forPanelFrame frame: CGRect, screenFrame: CGRect, imageSize: CGSize) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        guard imageBounds.width > 0, imageBounds.height > 0 else {
            return .zero
        }
        let travel = screenFrame.insetBy(dx: frame.width / 2, dy: 0)
        let fraction: CGFloat = travel.width > 0 ? ((frame.midX - travel.minX) / travel.width).clamped(to: 0 ... 1) : 0.5
        let scaleX = screenFrame.width > 0 ? imageBounds.width / screenFrame.width : 1
        let sampleHalfWidth = max(2, 150 * scaleX)
        let intersected = CGRect(
            x: imageBounds.width * fraction - sampleHalfWidth,
            y: 0,
            width: sampleHalfWidth * 2,
            height: imageBounds.height
        ).intersection(imageBounds)
        return intersected.isNull ? imageBounds : intersected
    }

    /// Publishes the average color of the strip behind the panel.
    ///
    /// The capture may be downscaled by WindowServer for low memory overhead. The panel's center is
    /// mapped to a fraction of its traversable range, and a proportional horizontal window of
    /// pixels around the matching strip position is averaged.
    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let capture = windowImage, capture.displayID == screen.displayID else {
            return
        }
        let image = capture.image
        let sampleRect = Self.sampleRect(
            forPanelFrame: frame,
            screenFrame: screen.frame,
            imageSize: CGSize(width: image.width, height: image.height)
        )

        guard
            !sampleRect.isEmpty, let sample = image.cropping(to: sampleRect), let averageColor = sample.averageColor()
        else {
            return
        }

        // The capture composites the menu bar and wallpaper windows; the
        // source label is nominal and does not track which one dominated.
        // Dragging across a uniform background resamples the same colour at
        // 10 Hz; an unchanged value must not animate the whole bar again.
        let info = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
        colorDisplayID = screen.displayID
        if colorInfo != info {
            colorInfo = info
        }
    }

    /// Refreshes capture and color for a panel that is about to be shown.
    ///
    /// Unlike refreshWhilePresented(animated:) this takes the frame and
    /// screen explicitly: ThawBar.show calls it before ordering the panel on
    /// screen, when isVisible is still false. Synchronous signature so the
    /// show path doesn't ripple async upstream.
    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        captureThenPublish(frame: frame, screen: screen, animated: false)
    }
}
