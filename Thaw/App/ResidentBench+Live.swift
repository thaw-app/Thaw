//
//  ResidentBench+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Darwin

/// `Thaw --bench-resident`: the real app, on the live menu bar, runs the stages in ResidentBench.swift and
/// quits, for scripts/bench-resident.sh. It shows and closes the Thaw Bar, search and Settings as a person
/// would, and moves no item and changes no setting itself.
extension ResidentBench {
    static let argument = "--bench-resident"

    /// Long enough for a login with many status items; without Accessibility the scan never starts.
    private static let scanTimeout: Duration = .seconds(120)

    private static var launchObserver: (any NSObjectProtocol)?

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Waits for the app to finish launching when the launch argument asks for a run. Called once,
    /// before the app's main; the delegate launches AppState as the app finishes launching.
    static func startAfterLaunchIfRequested() {
        guard isRequested else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { start() }
        }
    }

    private static func start() {
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
        }
        launchObserver = nil
        // A task, so the run starts after the delegate's own launch work, whichever observer ran first.
        Task {
            let problems: [String]
            if let appState = LiveApp.appState {
                problems = await ResidentBench(life: .live(appState), timing: Timing(), output: emit).run()
            } else {
                problems = ["the app did not start"]
                emit(Report.verdictLine(problems: problems))
            }
            if !problems.isEmpty {
                // AppKit ends a quit with exit(0), so a failed run swaps in its status after the quit work is done.
                atexit { _exit(1) }
            }
            // The normal quit, so Thaw's own quit work runs as it does for any quit.
            NSApp.terminate(nil)
        }
    }

    /// Flushed per line: the script reads the output from a file, and a quit would lose a buffered tail.
    private static func emit(_ line: String) {
        print(line)
        fflush(stdout)
    }

    fileprivate static func scanSettled(_ appState: AppState) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: scanTimeout)
        // Bootstrap makes the first scan when it reaches the item manager, and notes the launch settle with it.
        while appState.itemManager.initialCacheTask == nil {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await appState.itemManager.initialCacheTask?.value
        // Ends by the settle's own deadline even when the bar never steadies.
        await appState.barSettling.settled()
        return appState.itemManager.itemCache.displayID != nil
    }
}

extension ResidentBench.Life {
    static func live(_ appState: AppState) -> Self {
        let menuBarManager = appState.menuBarManager
        return Self(
            footprint: { MemoryReclaimer.physicalFootprint().map { Double($0) / 1_048_576 } },
            sleep: { duration in try? await Task.sleep(for: duration) },
            scanSettled: { await ResidentBench.scanSettled(appState) },
            thawBar: ResidentBench.Surface(
                name: "the Thaw Bar",
                show: {
                    guard let screen = NSScreen.activeMenuBarScreenOrMain else { return }
                    menuBarManager.thawBarPanel.show(section: .hidden, on: screen)
                },
                isShown: { menuBarManager.thawBarPanelIfCreated?.isVisible == true },
                // close(), not hide(): hide() would also hide the section on the live bar.
                close: { menuBarManager.thawBarPanelIfCreated?.close() }
            ),
            search: ResidentBench.Surface(
                name: "search",
                show: { menuBarManager.searchPanel.show() },
                isShown: { menuBarManager.searchPanelIfCreated?.isVisible == true },
                close: { menuBarManager.searchPanelIfCreated?.close() }
            ),
            settings: layoutSettings(appState),
            trimImageCache: { appState.imageCache.scheduleIdleTrim() },
            relieve: { MemoryReclaimer.scheduleRelief(reason: "resident benchmark") }
        )
    }

    /// Opens Settings in the app, not the settings process, as it does when the process hands Layout back.
    /// The page is saved as the last one shown, so the page from before goes back once the window is gone.
    private static func layoutSettings(_ appState: AppState) -> ResidentBench.Surface {
        let navigationState = appState.navigationState
        var pageBefore = navigationState.settingsNavigationIdentifier
        return ResidentBench.Surface(
            name: "Settings on the Layout page",
            show: {
                pageBefore = navigationState.settingsNavigationIdentifier
                navigationState.settingsNavigationIdentifier = .menuBarLayout
                appState.openWindow(.settings, allowSettingsProcess: false)
            },
            isShown: { navigationState.isSettingsPresented },
            close: {
                appState.dismissWindow(.settings)
                // Later, so the closing window never draws the earlier page.
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    navigationState.settingsNavigationIdentifier = pageBefore
                }
            }
        )
    }
}
