//
//  SettingsProcessHost.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Runs Settings in a process of its own, so its memory goes away when the window closes.
/// On unless SettingsInOwnProcess is turned off; the process reads the app's pipe and ends with the app.
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
        /// Each page's live state, commands and reloads.
        var features: [SettingsAppFeature] = []
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
    /// Whether messages still reach the settings process.
    var isLinked: Bool {
        link != nil
    }

    private var updatesWatch: Task<Void, Never>?
    private var statusWatches = [Task<Void, Never>]()
    /// Waits for the app's window to become key; a later window or the process ending cancels it.
    private var shownInAppWait: Task<Void, Never>?
    private let diagLog = DiagLog(category: "SettingsProcessHost")
    /// Hands the app's Settings window back to the settings process; see AppState.watchSettingsHandBack().
    let handBack = SettingsHandBack()

    init(
        app: AppSide,
        isEnabled: @escaping @MainActor () -> Bool = { SettingsProcessHost.isEnabledInDefaults() },
        launch: @escaping Launch = SettingsProcessHost.launchExecutable
    ) {
        self.app = app
        isEnabledNow = isEnabled
        launchChild = launch
    }

    /// Never in the settings process itself, which shows its own windows, nor in a unit-test run.
    static func isEnabledInDefaults(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        isEnabled(
            settingOn: Defaults.bool(forKey: .settingsInOwnProcess),
            isSettingsProcess: SettingsProcessApp.isRequested,
            isTestHost: TestHosting.isActive(environment: environment)
        )
    }

    static nonisolated func isEnabled(settingOn: Bool, isSettingsProcess: Bool, isTestHost: Bool) -> Bool {
        settingOn && !isSettingsProcess && !isTestHost
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
        return try launch(executable, arguments: arguments, onEnd: onEnd)
    }

    /// Starts executable with its standard input and output piped. Tests start a harmless tool.
    nonisolated static func launch(
        _ executable: URL,
        arguments: [String],
        onEnd: @escaping @Sendable (Int32) -> Void
    ) throws -> Child {
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
        watchStatuses()
        yieldActivation(to: child.processIdentifier)
        diagLog.info("Started the settings process (pid \(child.processIdentifier)) on \(pane)")
        return true
    }

    /// Tells a settings process that handed a pane over that the app's window is up, once that
    /// window is key, so the process closes its own window only then.
    func appWindowOpened(_ window: NSWindow) {
        shownInAppWait?.cancel()
        shownInAppWait = nil
        guard link != nil else { return }
        let becameKey = NotificationCenter.default.notifications(named: NSWindow.didBecomeKeyNotification, object: window)
        guard !window.isKeyWindow else {
            link?.send(.shownInApp)
            return
        }
        shownInAppWait = Task { @MainActor [weak self] in
            for await _ in becameKey {
                self?.link?.send(.shownInApp)
                break
            }
            if !Task.isCancelled {
                self?.shownInAppWait = nil
            }
        }
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
        statusWatches.forEach { $0.cancel() }
        statusWatches = []
        shownInAppWait?.cancel()
        shownInAppWait = nil
        app.features.forEach { $0.processEnded() }
    }

    private func receive(_ message: SettingsLinkMessage) {
        switch message {
        case .settingsChanged:
            link?.reloading {
                app.reloadSettings()
                app.features.forEach { $0.reload() }
            }
        case let .openInApp(pane):
            app.openInApp(pane)
        case let .pageChanged(pane):
            app.pageChanged(pane)
        case .checkForUpdates:
            app.checkForUpdates()
        case .quit:
            app.quit()
        case let .command(name, payload):
            run(name, payload)
        case let .storeChanged(store):
            link?.reloading { app.features.forEach { $0.stores[store]?() } }
        case let .request(id, name, payload):
            answer(id, name, payload)
        case .show, .updatesState, .shownInApp, .status, .reply:
            break
        }
    }

    /// Runs the page's request and sends back its answer, or the words of the error it threw.
    private func answer(_ id: UUID, _ name: String, _ payload: Data) {
        guard let handler = app.features.lazy.compactMap({ $0.requests[name] }).first else {
            diagLog.warning("The settings process asked \(name), which no page answers")
            link?.send(.reply(id: id, payload: nil, failure: "\(name)"))
            return
        }
        let asked = generation
        Task { @MainActor [weak self] in
            let reply: SettingsLinkMessage
            do {
                reply = try await .reply(id: id, payload: handler(payload), failure: nil)
            } catch {
                reply = .reply(id: id, payload: nil, failure: error.localizedDescription)
            }
            // A settings process started since would not know this request.
            guard let self, asked == generation else { return }
            link?.send(reply)
        }
    }

    private func run(_ command: String, _ payload: Data) {
        let handlers = app.features.compactMap { $0.commands[command] }
        if handlers.isEmpty {
            diagLog.warning("The settings process asked for \(command), which no page runs")
        }
        handlers.forEach { $0(payload) }
    }

    /// Sends a page's live state to the settings process, for state no observation reads.
    func send(status topic: String, payload: Data) {
        link?.send(.status(topic: topic, payload: payload))
    }

    /// Tells the settings process the app saved a store kept outside the defaults.
    func saved(store: String) {
        link?.send(.storeChanged(store: store))
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

    /// Sends each page's live state now and whenever it changes, leaving out a payload already sent.
    private func watchStatuses() {
        statusWatches = app.features.flatMap(\.statuses).map { topic, payload in
            Task { @MainActor [weak self] in
                var sent: Data?
                for await data in Observations({ payload() }) {
                    guard let data, data != sent else { continue }
                    sent = data
                    self?.link?.send(.status(topic: topic, payload: data))
                }
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
