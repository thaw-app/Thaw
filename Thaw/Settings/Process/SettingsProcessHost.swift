//
//  SettingsProcessHost.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Runs Settings in a process of its own, so its memory goes away when the window closes.
/// Off unless SettingsInOwnProcess is set; the process reads the app's pipe and ends with the app.
@MainActor
final class SettingsProcessHost {
    /// What the app does for the settings process.
    struct AppSide {
        var reloadSettings: () -> Void
        var openInApp: (String) -> Void
        var pageChanged: (String) -> Void
        var checkForUpdates: () -> Void
        var quit: () -> Void
        /// The updater state to send, read inside an observation so changes are sent too.
        var updatesState: () -> SettingsLinkMessage
    }

    private let app: AppSide
    private var process: Process?
    private var link: SettingsLinkEndpoint?
    private var updatesWatch: Task<Void, Never>?
    private let diagLog = DiagLog(category: "SettingsProcessHost")

    init(app: AppSide) {
        self.app = app
    }

    /// Never in the settings process itself, which shows its own windows.
    var isEnabled: Bool {
        Defaults.bool(forKey: .settingsInOwnProcess) && !SettingsProcessApp.isRequested
    }

    /// Shows Settings in its own process. Returns false when the app should show it instead.
    func show(pane: String, simpleMode: Bool) -> Bool {
        guard SettingsProcessRoute.runsInOwnProcess(pane: pane, simpleMode: simpleMode, isEnabled: isEnabled) else {
            return false
        }
        if let process, process.isRunning {
            link?.send(.show(pane: pane))
            yieldActivation(to: process)
            return true
        }
        return launch(pane: pane)
    }

    private func launch(pane: String) -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = [SettingsProcessRoute.launchArgument, pane]
        let toChild = Pipe()
        let fromChild = Pipe()
        process.standardInput = toChild
        process.standardOutput = fromChild
        process.terminationHandler = { [weak self] ended in
            Task { @MainActor in self?.ended(ended) }
        }
        do {
            try process.run()
        } catch {
            diagLog.error("Couldn't start the settings process: \(error)")
            return false
        }
        self.process = process
        link = SettingsLinkEndpoint(
            input: fromChild.fileHandleForReading,
            output: toChild.fileHandleForWriting,
            onMessage: { [weak self] message in self?.receive(message) }
        )
        watchUpdates()
        yieldActivation(to: process)
        diagLog.info("Started the settings process (pid \(process.processIdentifier)) on \(pane)")
        return true
    }

    private func ended(_ ended: Process) {
        guard ended === process else { return }
        diagLog.info("The settings process ended with status \(ended.terminationStatus)")
        process = nil
        link?.close()
        link = nil
        updatesWatch?.cancel()
        updatesWatch = nil
    }

    private func receive(_ message: SettingsLinkMessage) {
        switch message {
        case .settingsChanged:
            link?.reloading(app.reloadSettings)
        case let .openInApp(pane):
            app.openInApp(pane)
        case let .pageChanged(pane):
            app.pageChanged(pane)
        case .checkForUpdates:
            app.checkForUpdates()
        case .quit:
            app.quit()
        case .show, .updatesState:
            break
        }
    }

    /// Sends the updater state now and whenever it changes, for About and Privacy.
    private func watchUpdates() {
        let updatesState = app.updatesState
        updatesWatch = Task { @MainActor [weak self] in
            for await message in Observations({ updatesState() }) {
                self?.link?.send(message)
            }
        }
    }

    /// The system may hold back activation for a process the user didn't start.
    private func yieldActivation(to process: Process) {
        if let app = NSRunningApplication(processIdentifier: process.processIdentifier) {
            NSApp.yieldActivation(to: app)
        }
    }
}
