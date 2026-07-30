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

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag, windowID: CGWindowID?)
    }

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?
    @Published var editingItemTag: MenuBarItemTag?
    @Published var editingItemWindowID: CGWindowID?
    @Published var editingName: String = ""

    private var cancellables = Set<AnyCancellable>()

    /// Monotonically incremented by updateAverageColorInfo and
    /// clearAverageColorInfo. A capture in flight stamps the value it observed
    /// and only writes averageColorInfo on completion if the value still
    /// matches, so a late completion can't overwrite a freshly cleared value
    /// or a newer capture's result.
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
        .debounce(for: 0.1, scheduler: DispatchQueue.main) // Debounce to avoid rapid updates
        .sink { [weak self] screen in
            self?.updateAverageColorInfo(for: screen)
        }
        .store(in: &c)

        // Clear average color when search panel closes to free memory
        // and invalidate any in-flight capture from the open lifetime.
        panel.publisher(for: \.isVisible)
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.clearAverageColorInfo()
            }
            .store(in: &c)

        // Clear on display changes to prevent stale color info and invalidate
        // any in-flight capture targeting the previous screen geometry.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.clearAverageColorInfo()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Clears averageColorInfo and invalidates any in-flight capture so a late
    /// completion can't overwrite the cleared state with a stale value.
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

        // Stamp our generation before suspending. If clearAverageColorInfo or
        // a newer updateAverageColorInfo bumps the counter while we await, our
        // completion is stale and must skip the write so we don't undo an
        // intentional clear or clobber a fresher capture.
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
