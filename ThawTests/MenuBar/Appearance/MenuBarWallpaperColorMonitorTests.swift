//
//  MenuBarWallpaperColorMonitorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Testing
@testable import Thaw

/// The colour monitor before setup, where nothing may be sampled.
@MainActor
@Suite("Wallpaper colour monitor before setup", .serialized, .scratchDefaults)
struct MenuBarWallpaperColorMonitorTests {
    @Test("Without an app state a refresh samples nothing")
    func refreshWithoutSetup() async {
        let monitor = MenuBarWallpaperColorMonitor()
        await monitor.updateAverageColorInfoAsync()
        monitor.stopSettingsPreviewRefresh()
        #expect(monitor.averageColorInfo == nil)
        #expect(monitor.averageColors.isEmpty)
        #expect(monitor.wallpaperPalettes.isEmpty)
    }

    @Test("Without an app state only the settings, Space, display and sleep observers install")
    func observersWithoutSetup() {
        let monitor = MenuBarWallpaperColorMonitor()
        var bag = Set<AnyCancellable>()
        monitor.observeSettingsWindowReference(into: &bag)
        #expect(bag.isEmpty)
        monitor.observeSamplingTriggers(into: &bag)
        #expect(bag.count == 4)
    }

    @Test("The menu bar manager forwards the monitor's samples")
    func managerForwardsSamples() async {
        let manager = AppState().menuBarManager
        await manager.updateAverageColorInfoAsync()
        #expect(manager.averageColorInfo == manager.wallpaperColorMonitor.averageColorInfo)
        #expect(manager.averageColors == manager.wallpaperColorMonitor.averageColors)
        #expect(manager.wallpaperPalettes.isEmpty)
    }
}
