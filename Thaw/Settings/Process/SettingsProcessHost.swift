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

    /// A started settings process, as the host sees it.
    nonisolated struct Child {
        var processIdentifier: pid_t
        var isRunning: () -> Bool
        var fromChild: FileHandle
        var toChild: FileHandle
    }

    /// Starts the process with these arguments and calls the handler with its status once it ends.
    typealias Launch = @MainActor (_ arguments: [String], _ onEnd: @escaping @Sendable (Int32) -> Void) throws -> Child

    private let app: AppSide
    private let isEnabledNow: @MainActor () -> Bool
    private let launchChild: Launch
    private var child: Child?
    /// Counts the launches, so a process that ends after another has started is not taken for it.
    private var generation = 0
    private var link: SettingsLinkEndpoint?
    private var updatesWatch: Task<Void, Never>?
    private let diagLog = DiagLog(category: "SettingsProcessHost")

    init(
        app: AppSide,
        isEnabled: @escaping @MainActor () -> Bool = SettingsProcessHost.isEnabledInDefaults,
        launch: @escaping Launch = SettingsProcessHost.launchExecutable
    ) {
        self.app = app
        isEnabledNow = isEnabled
        launchChild = launch
    }

    /// Never in the settings process itself, which shows its own windows.
    static func isEnabledInDefaults() -> Bool {
        Defaults.bool(forKey: .settingsInOwnProcess) && !SettingsProcessApp.isRequested
    }

    /// Shows Settings in its own process. Returns false when the app should show it instead.
    func show(pane: String, simpleMode: Bool) -> Bool {
        guard SettingsProcessRoute.runsInOwnProcess(pane: pane, simpleMode: simpleMode, isEnabled: isEnabledNow()) else {
            return false
        }
        if let child, child.isRunning() {
            link?.send(.show(pane: pane))
            yieldActivation(to: child.processIdentifier)
            return true
        }
        return launch(pane: pane)
    }

    /// Starts this app's own executable with the settings argument, its standard input and output piped.
    nonisolated static func launchExecutable(
        arguments: [String],
        onEnd: @escaping @Sendable (Int32) -> Void
    ) throws -> Child {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let toChild = Pipe()
        let fromChild = Pipe()
        process.standardInput = toChild
        process.standardOutput = fromChild
        process.terminationHandler = { ended in onEnd(ended.terminationStatus) }
        try process.run()
        return Child(
            processIdentifier: process.processIdentifier,
            isRunning: { process.isRunning },
            fromChild: fromChild.fileHandleForReading,
            toChild: toChild.fileHandleForWriting
        )
    }

    private func launch(pane: String) -> Bool {
        let launched = generation + 1
        let child: Child
        do {
            child = try launchChild([SettingsProcessRoute.launchArgument, pane]) { [weak self] status in
                Task { @MainActor in self?.ended(generation: launched, status: status) }
            }
        } catch {
            diagLog.error("Couldn't start the settings process: \(error)")
            return false
        }
        generation = launched
        self.child = child
        link = SettingsLinkEndpoint(
            input: child.fromChild,
            output: child.toChild,
            onMessage: { [weak self] message in self?.receive(message) },
            onClose: { [weak self] in self?.linkClosed(generation: launched) }
        )
        watchUpdates()
        yieldActivation(to: child.processIdentifier)
        diagLog.info("Started the settings process (pid \(child.processIdentifier)) on \(pane)")
        return true
    }

    /// The process closed its end, so nothing more is sent to it.
    private func linkClosed(generation closed: Int) {
        guard closed == generation else { return }
        link = nil
    }

    private func ended(generation ended: Int, status: Int32) {
        guard ended == generation, child != nil else { return }
        diagLog.info("The settings process ended with status \(status)")
        child = nil
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
    private func yieldActivation(to processIdentifier: pid_t) {
        if let app = NSRunningApplication(processIdentifier: processIdentifier) {
            NSApp.yieldActivation(to: app)
        }
    }
}
