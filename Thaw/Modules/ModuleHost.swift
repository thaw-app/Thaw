//
//  ModuleHost.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation
import ThawModuleKit

/// Launches the installed modules the user switched on that pass ``ModuleLaunchRules``,
/// and restarts them when they quit on their own.
@MainActor
@Observable
final class ModuleHost {
    /// Everything the host needs from the system, so tests can replace it.
    struct Environment {
        /// Module bundles, downloaded ones first, so a downloaded copy wins
        /// over the bundled one with the same identifier.
        var listBundles: () -> [URL]
        var readInfo: (URL) -> [String: Any]?
        var teamID: (URL) -> String?
        var ownTeamID: () -> String?
        /// Launches a module, or brings a running one forward, and returns
        /// its process. With showWindow the module opens its window.
        var launch: (_ url: URL, _ showWindow: Bool) async throws -> pid_t
        var terminate: (pid_t) -> Void
        var now: () -> Date
        var wait: (TimeInterval) async -> Void
        /// The identifiers of the modules switched on, or nil before the first choice is saved.
        var loadEnabled: () -> Set<String>?
        var saveEnabled: (Set<String>) -> Void
        /// Whether a module starts switched on when nothing is saved yet:
        /// on when it has work from before it became a module.
        var enabledByDefault: (String) -> Bool
    }

    enum State: Equatable {
        case idle
        case refused(ModuleLaunchVerdict)
        case running(pid_t)
        case restarting
        case stopped
        case gaveUp
        case launchFailed
    }

    struct Module: Equatable {
        let manifest: ModuleManifest?
        let verdict: ModuleLaunchVerdict
        var state: State
    }

    private static let diagLog = DiagLog(category: "ModuleHost")

    /// The installed modules, keyed by bundle location.
    private(set) var modules: [URL: Module] = [:]

    /// The identifiers of the modules switched on.
    private(set) var enabledIdentifiers: Set<String> = []

    /// Called with a module's bundle ID whenever it stops running, whether it
    /// quit, crashed or was stopped, so Thaw can undo what it asked for.
    @ObservationIgnored var onModuleQuit: ((String) -> Void)?

    @ObservationIgnored private let environment: Environment
    @ObservationIgnored private let restartPolicy: ModuleRestartPolicy
    @ObservationIgnored private var crashes: [URL: [Date]] = [:]
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var hasLoadedEnabled = false

    init(environment: Environment, restartPolicy: ModuleRestartPolicy = ModuleRestartPolicy()) {
        self.environment = environment
        self.restartPolicy = restartPolicy
        // A saved choice is known before the first scan, so the sidebar and
        // Settings can ask isEnabled straight away. Without one, the first
        // scan picks the defaults, since they depend on what is installed.
        if let saved = environment.loadEnabled() {
            enabledIdentifiers = saved
            hasLoadedEnabled = true
        }
    }

    static func modulesDirectory(applicationSupport: URL = .applicationSupportDirectory) -> URL {
        applicationSupport.appending(path: ThawMenuBarIdentity.bundleIdentifier).appending(path: "Modules")
    }

    static func bundledModulesDirectory(appBundle: URL = Bundle.main.bundleURL) -> URL {
        appBundle.appending(path: "Contents/Library/Modules")
    }

    /// Rereads the Modules folder. Modules already known keep their state.
    func refresh() {
        let ownTeamID = environment.ownTeamID()
        var found: [URL: Module] = [:]
        var identifiers = Set<String>()
        for url in environment.listBundles() {
            let manifest = environment.readInfo(url).flatMap(ModuleManifest.init(infoDictionary:))
            if let identifier = manifest?.identifier {
                guard identifiers.insert(identifier).inserted else { continue }
            }
            let verdict = ModuleLaunchRules.verdict(
                manifest: manifest,
                moduleTeamID: environment.teamID(url),
                ownTeamID: ownTeamID
            )
            // A module that may not run says why straight away, so Modules can
            // show the reason before anyone switches it on.
            let known = modules[url]?.state ?? .idle
            let state: State = verdict == .launch || known != .idle ? known : .refused(verdict)
            found[url] = Module(manifest: manifest, verdict: verdict, state: state)
        }
        modules = found
        loadEnabledIfNeeded()
    }

    func isEnabled(_ identifier: String) -> Bool {
        enabledIdentifiers.contains(identifier)
    }

    func isEnabled(_ module: ModuleIdentifier) -> Bool {
        isEnabled(module.rawValue)
    }

    /// Switches a module on or off, saves the choice, and starts or stops it.
    func setEnabled(_ enabled: Bool, identifier: String) async {
        if enabled {
            enabledIdentifiers.insert(identifier)
        } else {
            enabledIdentifiers.remove(identifier)
        }
        environment.saveEnabled(enabledIdentifiers)
        Self.diagLog.info("Module \(identifier) switched \(enabled ? "on" : "off")")
        guard let url = url(ofModule: identifier) else {
            Self.diagLog.warning("Module \(identifier) is not installed")
            return
        }
        if enabled {
            await start(url)
        } else {
            stop(url)
        }
    }

    /// Reads the saved choice once. On a first run nothing is saved, so each
    /// installed module takes its default and the result is saved.
    private func loadEnabledIfNeeded() {
        guard !hasLoadedEnabled else { return }
        hasLoadedEnabled = true
        if let saved = environment.loadEnabled() {
            enabledIdentifiers = saved
            return
        }
        let identifiers = modules.values.compactMap(\.manifest?.identifier)
        enabledIdentifiers = Set(identifiers.filter(environment.enabledByDefault))
        environment.saveEnabled(enabledIdentifiers)
    }

    /// Where the module with this identifier is installed, if it is.
    func url(ofModule identifier: String) -> URL? {
        modules.first { $0.value.manifest?.identifier == identifier }?.key
    }

    func url(ofModule module: ModuleIdentifier) -> URL? {
        url(ofModule: module.rawValue)
    }

    /// Rereads the folders and launches every module that may run and isn't running yet.
    func startAll() async {
        refresh()
        for (url, module) in modules where module.verdict == .launch {
            guard let identifier = module.manifest?.identifier, isEnabled(identifier) else { continue }
            switch module.state {
            case .idle, .stopped, .launchFailed:
                await start(url)
            case .refused, .running, .restarting, .gaveUp:
                break
            }
        }
    }

    /// Opens a module's window, launching it first when it isn't running,
    /// so the process is one this host tracks and restarts.
    func openWindow(of module: ModuleIdentifier) async {
        guard let url = url(ofModule: module) else { return }
        await start(url, showingWindow: true)
    }

    func start(_ url: URL, showingWindow: Bool = false) async {
        guard let module = modules[url] else { return }
        guard module.verdict == .launch else {
            Self.diagLog.info("Module at \(url.path) not launched: \(String(describing: module.verdict))")
            modules[url]?.state = .refused(module.verdict)
            return
        }
        do {
            let pid = try await environment.launch(url, showingWindow)
            // A module that quits while it starts, such as one dyld can't
            // load, comes back with no process, so it never ran.
            guard pid > 0 else {
                Self.diagLog.error("Module at \(url.path) quit as it launched")
                modules[url]?.state = .launchFailed
                return
            }
            Self.diagLog.info("Module at \(url.lastPathComponent) running as pid \(pid)")
            modules[url]?.state = .running(pid)
        } catch {
            Self.diagLog.error("Module at \(url.path) failed to launch: \(error)")
            modules[url]?.state = .launchFailed
        }
    }

    func stop(_ url: URL) {
        guard let state = modules[url]?.state else { return }
        modules[url]?.state = .stopped
        if case let .running(pid) = state {
            Self.diagLog.info("Stopping module at \(url.lastPathComponent), pid \(pid)")
            environment.terminate(pid)
            reportQuit(url)
        }
    }

    private func reportQuit(_ url: URL) {
        if let bundleIdentifier = modules[url]?.manifest?.bundleIdentifier {
            onModuleQuit?(bundleIdentifier)
        }
    }

    func stopAll() {
        for url in modules.keys {
            if case .running = modules[url]?.state {
                stop(url)
            }
        }
    }

    /// Called when any app quits. A module that quits while still marked
    /// running did so on its own, and the restart policy decides what's next.
    func moduleDidTerminate(pid: pid_t) async {
        guard let url = modules.first(where: { $0.value.state == .running(pid) })?.key else { return }
        reportQuit(url)
        let now = environment.now()
        crashes[url, default: []].append(now)
        switch restartPolicy.decision(crashes: crashes[url] ?? [], now: now) {
        case .stop:
            Self.diagLog.error("Module at \(url.path) keeps quitting; not restarting it")
            modules[url]?.state = .gaveUp
        case let .restart(after: delay):
            modules[url]?.state = .restarting
            await environment.wait(delay)
            guard modules[url]?.state == .restarting else { return }
            await start(url)
        }
    }

    /// Watches for module processes quitting. Call once after creating the live host.
    func startObservingTerminations() {
        guard terminationObserver == nil else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            Task { @MainActor in
                await self?.moduleDidTerminate(pid: pid)
            }
        }
    }
}
