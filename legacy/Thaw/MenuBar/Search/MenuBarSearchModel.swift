//
//  MenuBarSearchModel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Ifrit
import Observation

@MainActor
@Observable
final class MenuBarSearchModel {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag, windowID: CGWindowID?)
    }

    var searchText = ""
    var displayedItems = [SectionedListItem<ItemID>]()
    var selection: ItemID?
    private(set) var averageColorInfo: MenuBarAverageColorInfo?
    var editingItemTag: MenuBarItemTag?
    var editingItemWindowID: CGWindowID?
    var editingName: String = ""

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Bumped on every capture and clear. A capture only writes its result if
    /// the value still matches, so a late completion can't clobber newer state.
    private var captureGeneration: Int = 0

    let fuse = Fuse(threshold: 0.5)

    func performSetup(with panel: MenuBarSearchPanel) {
        configureCancellables(with: panel)
    }

    private func configureCancellables(with panel: MenuBarSearchPanel) {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            panel.publisher(for: \.screen),
            panel.publisher(for: \.isVisible)
        )
        .compactMap { screen, isVisible in
            isVisible ? screen : nil
        }
        .debounce(for: 0.1, scheduler: DispatchQueue.main)
        .sink { [weak self] screen in
            self?.updateAverageColorInfo(for: screen)
        }
        .store(in: &c)

        // Free the color on close and invalidate any in-flight capture.
        panel.publisher(for: \.isVisible)
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.clearAverageColorInfo()
            }
            .store(in: &c)

        // Display changes invalidate captures of the old screen geometry.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.clearAverageColorInfo()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Clears averageColorInfo and invalidates any in-flight capture.
    private func clearAverageColorInfo() {
        captureGeneration += 1
        averageColorInfo = nil
    }

    private func updateAverageColorInfo(for screen: NSScreen) {
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

        // Stamp the generation before suspending; see `captureGeneration`.
        captureGeneration += 1
        let generation = captureGeneration

        Task { [weak self] in
            guard
                let image = await ScreenCapture.captureWindowsAsync(
                    with: windowIDs,
                    screenBounds: bounds,
                    option: .nominalResolution
                ),
                let color = image.averageColor(option: .ignoreAlpha)
            else {
                return
            }
            guard let self, generation == self.captureGeneration else { return }
            let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)
            if self.averageColorInfo != info {
                self.averageColorInfo = info
            }
        }
    }
}
