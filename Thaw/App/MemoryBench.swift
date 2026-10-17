//
//  MemoryBench.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// `Thaw --bench-memory`: draws every Settings pane and Search off screen and prints the memory held,
/// for scripts/check-memory-budget.sh. Nothing is launched and settings go to a scratch suite.
@MainActor
enum MemoryBench {
    static let argument = "--bench-memory"
    private static let suiteName = "com.stonerl.Thaw.memory-bench"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func run() -> Never {
        _ = NSApplication.shared
        UserDefaults().removePersistentDomain(forName: suiteName)
        if let scratch = UserDefaults(suiteName: suiteName) {
            Defaults.store = scratch
        }
        let appState = AppState()
        report("LAUNCH")

        benchSettings(appState)
        benchSearch(appState)

        print("FOOTPRINT \(String(format: "%.1f", footprintMegabytes())) MB")
        print("HEAP \(String(format: "%.1f", heapMegabytes())) MB")
        UserDefaults().removePersistentDomain(forName: suiteName)
        if let hold = ProcessInfo.processInfo.environment["THAW_BENCH_HOLD"].flatMap(Double.init) {
            settle(hold)
        }
        exit(0)
    }

    private static func benchSettings(_ appState: AppState) {
        let settings = window(size: SettingsWindowMetrics.fullDefault)
        settings.contentView = NSHostingView(rootView: SettingsView(
            appState: appState,
            navigationState: appState.navigationState,
            generalSettings: appState.settings.general
        )
        .environment(appState)
        .environment(appState.permissions))
        for pane in SettingsNavigationIdentifier.allCases {
            appState.navigationState.settingsNavigationIdentifier = pane
            render(settings)
            if ProcessInfo.processInfo.environment["THAW_BENCH_PANES"] != nil {
                report("PANE \(pane.rawValue)")
            }
        }
        report("SETTINGS")
        settings.contentView = nil
        settings.close()
        settle(0.5)
        report("SETTINGS CLOSED")
    }

    private static func benchSearch(_ appState: AppState) {
        let search = window(size: CGSize(width: 640, height: 480))
        let model = MenuBarSearchModel()
        search.contentView = NSHostingView(rootView: MenuBarSearchRootView(
            appState: appState,
            model: model,
            displayID: CGMainDisplayID(),
            panel: MenuBarSearchPanel(),
            presentation: .inspector
        ))
        render(search)
        for query in ["wi", "wifi", "battery", ""] {
            model.searchText = query
            render(search)
        }
        report("SEARCH")
        search.contentView = nil
        search.close()
        settle(0.5)
        _ = malloc_zone_pressure_relief(nil, 0)
    }

    private static func window(size: CGSize) -> NSWindow {
        let frame = NSRect(origin: NSPoint(x: -6000, y: -6000), size: size)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }

    private static func render(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        settle(0.05)
    }

    private static func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Freed pages go back first, as MemoryReclaimer does after a panel closes, so the figure is what is held.
    private static func report(_ step: String) {
        settle(0.3)
        _ = malloc_zone_pressure_relief(nil, 0)
        print("STEP \(step) \(String(format: "%.1f", footprintMegabytes())) MB, heap \(String(format: "%.1f", heapMegabytes())) MB")
    }

    /// Bytes the allocator has handed out and not had back: steadier than the footprint,
    /// which also counts graphics buffers and pages the allocator hasn't returned yet.
    private static func heapMegabytes() -> Double {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Double(stats.size_in_use) / 1_048_576
    }

    private static func footprintMegabytes() -> Double {
        Double(MemoryReclaimer.physicalFootprint() ?? 0) / 1_048_576
    }
}
