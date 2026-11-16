//
//  SettingsLink+Modules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// What the Modules, Widgets and Scripts pages send over the link. The app owns the module
/// processes, so the settings process shows the app's modules and has the app start and switch them.
nonisolated enum ModulesLink {
    /// The topic of the app's modules and switches.
    static let state = "modules.state"
    /// Read the Modules folders again.
    static let refresh = "modules.refresh"
    /// Switch a module on or off, with a Switch.
    static let setEnabled = "modules.setEnabled"
    /// Start a module or open its window, with a Start.
    static let start = "modules.start"

    /// An installed module and where it is.
    struct Entry: Codable, Equatable {
        var url: URL
        var module: ModuleHost.Module
    }

    /// The installed modules and the ones switched on, both in a fixed order, so the same
    /// state is always the same payload and is sent once.
    struct State: Codable, Equatable {
        var modules: [Entry]
        var enabled: [String]

        init(modules: [URL: ModuleHost.Module], enabled: Set<String>) {
            self.modules = modules
                .map { Entry(url: $0.key, module: $0.value) }
                .sorted { $0.url.absoluteString < $1.url.absoluteString }
            self.enabled = enabled.sorted()
        }

        var modulesByURL: [URL: ModuleHost.Module] {
            Dictionary(modules.map { ($0.url, $0.module) }, uniquingKeysWith: { first, _ in first })
        }

        /// The state with its keys in order. Left to itself the encoder writes an object's keys
        /// in an order that changes from one encoding to the next.
        var payload: Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try? encoder.encode(self)
        }
    }

    /// A module switched on or off, by its identifier.
    struct Switch: Codable, Equatable {
        var identifier: String
        var enabled: Bool
    }

    /// A module to start, with its window when the user opened it. By its identifier, since
    /// the app looks up where the module is installed itself.
    struct Start: Codable, Equatable {
        var identifier: String
        var showingWindow: Bool
    }
}

extension ModuleHost {
    /// What only the process that owns the modules does.
    enum Request {
        case refresh
        case setEnabled(Bool, identifier: String)
        case start(URL, showingWindow: Bool)
    }

    /// True in the settings process until the app's modules have arrived, so a page doesn't
    /// call a module missing before it knows.
    var awaitsModules: Bool {
        remote() != nil && !hasMirrored
    }

    /// In the settings process, has the app do this and returns true. False in the app, which
    /// does it itself.
    func forwards(_ request: Request) -> Bool {
        guard let remote = remote() else { return false }
        switch request {
        case .refresh:
            remote.perform(ModulesLink.refresh)
        case let .setEnabled(enabled, identifier):
            // The switch shows the choice at once. The app's modules follow and have the last word.
            let shown = enabled ? enabledIdentifiers.union([identifier]) : enabledIdentifiers.subtracting([identifier])
            mirror(modules: modules, enabledIdentifiers: shown)
            remote.perform(ModulesLink.setEnabled, ModulesLink.Switch(identifier: identifier, enabled: enabled))
        case let .start(url, showingWindow):
            guard let module = modules[url], let identifier = module.manifest?.identifier else { break }
            if showingWindow {
                yieldActivation(toModuleIn: module.state)
            }
            remote.perform(ModulesLink.start, ModulesLink.Start(identifier: identifier, showingWindow: showingWindow))
        }
        return true
    }

    /// The settings process is in front, so the module's window may only come forward if this
    /// process lets the module, or the app that starts it, become active.
    private func yieldActivation(toModuleIn state: State) {
        let pid = if case let .running(pid) = state { pid } else { getppid() }
        if let app = NSRunningApplication(processIdentifier: pid) {
            NSApp.yieldActivation(to: app)
        }
    }
}

extension SettingsAppFeature {
    /// The app's share of Modules, Widgets and Scripts: it sends its modules and switches, does
    /// what the pages ask of them, and follows the Profiles switch the settings process saved.
    static func modules(host: ModuleHost, profiles: ProfilesFeature) -> SettingsAppFeature {
        SettingsAppFeature(
            statuses: [
                ModulesLink.state: { ModulesLink.State(modules: host.modules, enabled: host.enabledIdentifiers).payload },
            ],
            commands: [
                ModulesLink.refresh: { _ in host.refresh() },
                ModulesLink.setEnabled: { payload in
                    guard let change = SettingsLinkPayload.decode(ModulesLink.Switch.self, from: payload) else { return }
                    Task { await host.setEnabled(change.enabled, identifier: change.identifier) }
                },
                ModulesLink.start: { payload in
                    guard let request = SettingsLinkPayload.decode(ModulesLink.Start.self, from: payload),
                          let url = host.url(ofModule: request.identifier)
                    else {
                        return
                    }
                    Task { await host.start(url, showingWindow: request.showingWindow) }
                },
            ],
            // Setting the switch here also does what follows from it, such as the profile shortcuts.
            reload: { profiles.isOn = ProfilesFeature.isOnInDefaults }
        )
    }
}

extension SettingsChildFeature {
    /// The settings process's share: its module host shows the app's modules and switches, and
    /// its Profiles switch follows the one the app saved.
    static func modules(host: ModuleHost, profiles: ProfilesFeature) -> SettingsChildFeature {
        SettingsChildFeature(
            statuses: [
                ModulesLink.state: { payload in
                    guard let state = SettingsLinkPayload.decode(ModulesLink.State.self, from: payload) else { return }
                    host.mirror(modules: state.modulesByURL, enabledIdentifiers: Set(state.enabled))
                },
            ],
            reload: { profiles.isOn = ProfilesFeature.isOnInDefaults }
        )
    }
}
