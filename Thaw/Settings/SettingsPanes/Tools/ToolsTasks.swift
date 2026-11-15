//
//  ToolsTasks.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import PlatformRuntimeKit

/// Work the Troubleshooting page asks for that only the running app can do. Its settings process
/// sends one over the link, after the person confirmed it there.
nonisolated enum ToolsTask: Codable, Equatable, Sendable {
    case run(MaintenanceToolAction)
    /// Quit Thaw and open the window that restores missing menu bar items.
    case openRecovery
    /// Write a fresh item list beside the logs and say where it is.
    case writeItemList
    /// Put back the layout backup kept at this location.
    case restoreBackup(URL)
}

/// What a task says while it runs. The last two only cross the link, which can't carry a thrown error.
nonisolated enum ToolsTaskEvent: Codable, Equatable, Sendable {
    /// Text for beside the button, such as what was reset.
    case message(String)
    /// How many files a restore wrote back, and how many it couldn't.
    case restored(written: Int, skipped: Int)
    /// Where the item list was written.
    case itemList(URL)
    case finished
    case failed(String)
}

/// Does the page's tasks in the running app, which has the menu bar engine. Each step is a
/// closure, so a test runs a task without resetting, restarting or quitting anything.
@MainActor
struct ToolsTaskPerformer {
    var waitForMoves: () async -> Void
    var resetSettings: () -> Void
    /// Returns the name of the backup it wrote first, or nil when there was nothing to back up.
    var rebuildSavedLayout: () async throws -> String?
    var forgetStrandedRepairs: () -> Void
    var layoutTableExists: () -> Bool
    var pause: (Duration) async -> Void
    var restartMenuBar: () async throws -> Void
    var resetPermissions: () async throws -> Void
    var chooseReducedMode: () -> Void
    var openRecovery: () async throws -> Void
    var writeItemList: () throws -> URL
    var restoreBackup: (URL) async throws -> (written: Int, skipped: Int)
    var relaunch: () -> Void
    var quit: () -> Void

    /// Runs task to its end, reporting as it goes, and throws what the task failed with.
    func perform(_ task: ToolsTask, report: (ToolsTaskEvent) -> Void) async throws {
        switch task {
        case let .run(action):
            try await run(action) { report(.message($0)) }
        case .openRecovery:
            try await openRecovery()
        case .writeItemList:
            try report(.itemList(writeItemList()))
        case let .restoreBackup(backup):
            // Killing the host mid-move strands the move's events.
            await waitForMoves()
            let outcome = try await restoreBackup(backup)
            report(.restored(written: outcome.written, skipped: outcome.skipped))
        }
    }

    private func run(_ action: MaintenanceToolAction, say: (String) -> Void) async throws {
        if action == .resetMenuBarLayoutPositions || action == .restartMenuBar {
            // Killing the host mid-move strands the move's events.
            await waitForMoves()
        }
        switch action {
        case .resetSettings:
            resetSettings()
            say(String(localized: "Settings were reset to defaults."))
        case .resetMenuBarLayoutPositions:
            let backup = try await rebuildSavedLayout()
            forgetStrandedRepairs()
            if let backup {
                say(String(localized: "macOS's saved layout was deleted. Backup saved as \(backup). Relaunching…"))
            } else {
                say(String(localized: "macOS's saved layout was deleted. Relaunching…"))
            }
            // Access granted to the old layout table does not carry over to
            // the one the menu bar writes next, so relaunch once it exists.
            for _ in 0 ..< 60 where !layoutTableExists() {
                await pause(.milliseconds(500))
            }
            relaunch()
        case .restartMenuBar:
            try await restartMenuBar()
            say(String(localized: "The menu bar was restarted. Relaunching…"))
            // Thaw's hiding and positions sessions ended with the old host.
            relaunch()
        case .resetPermissions:
            try await resetPermissions()
            say(String(localized: "Permissions cleared. Quitting…"))
            quit()
        case .enterReducedMode:
            chooseReducedMode()
            relaunch()
        }
    }

    /// The steps as the running app takes them.
    static func live(_ appState: AppState) -> ToolsTaskPerformer {
        ToolsTaskPerformer(
            waitForMoves: { await appState.itemManager.moveActivity.waitUntilIdle() },
            resetSettings: { appState.settings.resetAllSettingsToDefaults() },
            rebuildSavedLayout: { try await MaintenanceTools.resetMenuBarLayoutPositions()?.url.lastPathComponent },
            forgetStrandedRepairs: { appState.itemManager.forgetStrandedRepairs() },
            layoutTableExists: {
                FileManager.default.fileExists(atPath: MenuBarLayoutTableAccess.tableURL.path(percentEncoded: false))
            },
            pause: { try? await Task.sleep(for: $0) },
            restartMenuBar: { try await MaintenanceTools.restartMenuBar() },
            resetPermissions: { try await MaintenanceTools.resetAppPermissions() },
            chooseReducedMode: { ReducedModeController.choose(keepingWithAccessibility: true) },
            openRecovery: { try await NativeVisibilityRecoveryLaunch.openRecovery() },
            writeItemList: { try MaintenanceTools.writeItemList() },
            restoreBackup: { try await restore(backupAt: $0, among: MenuBarLayoutBackups.list()) },
            relaunch: { appState.restartSelf() },
            quit: { ApplicationTermination.request() }
        )
    }

    /// Restores the backup read from disk just now, never one described by another process.
    private static func restore(
        backupAt location: URL,
        among backups: [MenuBarLayoutBackups.Backup]
    ) async throws -> (written: Int, skipped: Int) {
        guard let backup = backups.first(where: { $0.url.standardizedFileURL == location.standardizedFileURL }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: location])
        }
        let outcome = try await MaintenanceTools.restoreMenuBarLayout(from: backup)
        return (outcome.restored.count, outcome.skipped.count)
    }
}

/// Where the Troubleshooting page's work runs: in this process when Settings is one of the app's
/// windows, or in the app when this is its settings process.
@MainActor
enum ToolsTasks {
    /// Runs task, reporting as it goes, and throws what it failed with. A failure in the app
    /// arrives as its text.
    static func perform(
        _ task: ToolsTask,
        appState: AppState,
        remote: SettingsRemote? = .current,
        local: @MainActor (AppState) -> ToolsTaskPerformer = ToolsTaskPerformer.live,
        report: (ToolsTaskEvent) -> Void = { _ in /* Most tasks say nothing the page shows. */ }
    ) async throws {
        guard let remote else {
            return try await local(appState).perform(task, report: report)
        }
        try await appState.settings.tools.appReport.perform(task, via: remote, report: report)
        if task == .run(.resetSettings) {
            forgetWhatResetCleared(in: appState.settings)
        }
    }

    /// Relaunches Thaw. Asked from the settings process, the app relaunches and that process ends with it.
    static func relaunch(
        _ appState: AppState,
        remote: SettingsRemote? = .current,
        local: (AppState) -> Void = { $0.restartSelf() }
    ) {
        if let remote {
            remote.perform(ToolsLink.relaunch)
        } else {
            local(appState)
        }
    }

    /// After the app reset every setting, the settings process reads the stored values again when
    /// the app's writes reach it. This drops what it keeps only in memory, which that never reads.
    static func forgetWhatResetCleared(in settings: AppSettings, hints: FirstRunHintStore = .shared) {
        settings.general.lastCustomThawIcon = nil
        hints.reset()
    }
}
