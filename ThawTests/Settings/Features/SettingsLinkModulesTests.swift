//
//  SettingsLinkModulesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import os
import SwiftUI
import Testing
@testable import Thaw
import ThawModuleKit

/// What a module host in the settings process asked the app for.
@MainActor
private final class AppRequests {
    private(set) var messages = [SettingsLinkMessage]()
    private(set) lazy var remote = SettingsRemote { [weak self] in self?.messages.append($0) }

    /// The payloads of the commands with this name, in the order they were sent.
    func payloads<Payload: Decodable>(_: Payload.Type, of name: String) -> [Payload] {
        messages.compactMap { message in
            guard case .command(name: name, let payload) = message else { return nil }
            return SettingsLinkPayload.decode(Payload.self, from: payload)
        }
    }
}

@Suite("Settings process link for modules")
@MainActor
struct SettingsLinkModulesTests {
    private typealias FakeSystem = ModuleHostTests.FakeSystem

    /// The app's system, whose modules its host lists, starts and stops.
    private let system = FakeSystem()
    /// The settings process's system. Its host must leave it alone.
    private let settingsSystem = FakeSystem()
    private let requests = AppRequests()

    /// The app's host, which owns the modules.
    private func appHost() -> ModuleHost {
        let host = ModuleHost(environment: system.environment())
        host.remote = { nil }
        host.refresh()
        return host
    }

    /// The settings process's host, which reaches the app through requests.
    private func settingsHost() -> ModuleHost {
        let host = ModuleHost(environment: settingsSystem.environment())
        host.remote = { [requests] in requests.remote }
        return host
    }

    private func module(_ identifier: String, state: ModuleHost.State = .idle) -> ModuleHost.Module {
        ModuleHost.Module(
            manifest: ModuleManifest(identifier: identifier, name: identifier.capitalized, bundleIdentifier: "com.thaw.module.\(identifier)", version: "1", minimumAPIVersion: 1),
            verdict: .launch,
            state: state
        )
    }

    private func modulesState(of feature: SettingsAppFeature) throws -> ModulesLink.State {
        let payload = try #require(feature.statuses[ModulesLink.state]?())
        return try #require(SettingsLinkPayload.decode(ModulesLink.State.self, from: payload))
    }

    // MARK: Payloads

    @Test("The modules and switches survive the trip, and the same state is the same payload")
    func stateRoundTrip() throws {
        let widgets = URL(filePath: "/Modules/widgets.app")
        let triggers = URL(filePath: "/Modules/triggers.app")
        let stray = URL(filePath: "/Modules/stray.app")
        let newer = ModuleLaunchVerdict.needsNewerThaw(requiredAPIVersion: 3)
        let listed: [(URL, ModuleHost.Module)] = [
            (widgets, module("widgets", state: .running(42))),
            (triggers, ModuleHost.Module(manifest: module("triggers").manifest, verdict: newer, state: .refused(newer))),
            (stray, ModuleHost.Module(manifest: nil, verdict: .notAModule, state: .gaveUp)),
        ]
        let modules = Dictionary(uniqueKeysWithValues: listed)
        let state = ModulesLink.State(modules: modules, enabled: ["widgets", "automation"])
        let payload = try #require(state.payload)
        let decoded = try #require(SettingsLinkPayload.decode(ModulesLink.State.self, from: payload))
        #expect(decoded == state)
        #expect(decoded.modulesByURL == modules)
        #expect(decoded.enabled == ["automation", "widgets"])

        let listedBackwards = Dictionary(uniqueKeysWithValues: listed.reversed())
        let again = ModulesLink.State(modules: listedBackwards, enabled: ["automation", "widgets"])
        #expect(again.payload == payload, "The order the modules were listed in doesn't change the payload")
    }

    @Test("A switch and a start survive the trip")
    func commandRoundTrips() throws {
        let change = ModulesLink.Switch(identifier: "widgets", enabled: true)
        let start = ModulesLink.Start(identifier: "automation", showingWindow: true)
        #expect(try SettingsLinkPayload.decode(ModulesLink.Switch.self, from: #require(SettingsLinkPayload.encode(change))) == change)
        #expect(try SettingsLinkPayload.decode(ModulesLink.Start.self, from: #require(SettingsLinkPayload.encode(start))) == start)
    }

    // MARK: The app's side

    @Test("The app sends its modules and switches, and sends them again when they change")
    func appSendsItsModules() async throws {
        let widgets = system.addModule("widgets")
        system.savedEnabled = []
        let host = appHost()
        let feature = SettingsAppFeature.modules(host: host, profiles: ProfilesFeature())

        let before = try modulesState(of: feature)
        #expect(before.modulesByURL == host.modules)
        #expect(before.enabled.isEmpty)

        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = feature.statuses[ModulesLink.state]?()
        } onChange: {
            changed.withLock { $0 = true }
        }
        await host.setEnabled(true, identifier: "widgets")
        #expect(changed.withLock { $0 }, "The link sends a topic again when what it read changes")

        let after = try modulesState(of: feature)
        #expect(after.enabled == ["widgets"])
        #expect(after.modulesByURL[widgets]?.state == .running(101))

        let sent = feature.statuses[ModulesLink.state]?()
        host.refresh()
        #expect(feature.statuses[ModulesLink.state]?() == sent, "Listing the same modules again is the same payload, which the link sends once")
    }

    @Test("The app switches, opens and lists modules when the settings process asks")
    func appRunsCommands() async throws {
        let widgets = system.addModule("widgets")
        system.savedEnabled = []
        let host = appHost()
        let feature = SettingsAppFeature.modules(host: host, profiles: ProfilesFeature())
        func run(_ name: String, _ payload: some Encodable) throws {
            try feature.commands[name]?(#require(SettingsLinkPayload.encode(payload)))
        }

        try run(ModulesLink.setEnabled, ModulesLink.Switch(identifier: "widgets", enabled: true))
        #expect(await settingsLinkWait { host.modules[widgets]?.state == .running(101) })
        #expect(system.savedEnabled == ["widgets"])
        #expect(system.launched == [widgets])
        #expect(system.windowsShown.isEmpty)

        try run(ModulesLink.start, ModulesLink.Start(identifier: "widgets", showingWindow: true))
        #expect(await settingsLinkWait { system.windowsShown == [widgets] })

        try run(ModulesLink.setEnabled, ModulesLink.Switch(identifier: "widgets", enabled: false))
        #expect(await settingsLinkWait { host.modules[widgets]?.state == .stopped })
        #expect(system.savedEnabled == [])
        #expect(system.terminated == [102])

        let triggers = system.addModule("triggers")
        feature.commands[ModulesLink.refresh]?(Data())
        #expect(host.modules[triggers]?.verdict == .launch)
    }

    @Test("A command the app can't read, or for a module that isn't installed, starts nothing")
    func appIgnoresWhatItCannotRun() async throws {
        _ = system.addModule("widgets")
        system.savedEnabled = []
        let host = appHost()
        let feature = SettingsAppFeature.modules(host: host, profiles: ProfilesFeature())

        feature.commands[ModulesLink.setEnabled]?(Data("nonsense".utf8))
        feature.commands[ModulesLink.start]?(Data())
        try feature.commands[ModulesLink.start]?(#require(SettingsLinkPayload.encode(ModulesLink.Start(identifier: "missing", showingWindow: true))))
        for _ in 0 ..< 3 {
            await mainActorQueueDrained()
        }
        #expect(system.launchesBegun == 0)
        #expect(system.savedEnabled == [])
        #expect(host.enabledIdentifiers.isEmpty)
    }

    // MARK: The settings process's side

    @Test("The settings process shows the app's modules and switches")
    func settingsProcessMirrorsTheApp() async throws {
        let widgets = system.addModule("widgets")
        let app = appHost()
        await app.setEnabled(true, identifier: "widgets")
        let payload = try #require(SettingsAppFeature.modules(host: app, profiles: ProfilesFeature()).statuses[ModulesLink.state]?())

        let host = settingsHost()
        let feature = SettingsChildFeature.modules(host: host, profiles: ProfilesFeature())
        #expect(host.awaitsModules)
        #expect(!app.awaitsModules, "The app lists its modules itself")

        feature.statuses[ModulesLink.state]?(Data("nonsense".utf8))
        #expect(host.awaitsModules, "A payload it can't read changes nothing")

        feature.statuses[ModulesLink.state]?(payload)
        #expect(!host.awaitsModules)
        #expect(host.modules == app.modules)
        #expect(host.url(ofModule: .widgets) == widgets)
        #expect(host.modules[widgets]?.state == .running(101))
        #expect(host.isEnabled(.widgets))

        await app.setEnabled(false, identifier: "widgets")
        try feature.statuses[ModulesLink.state]?(#require(SettingsAppFeature.modules(host: app, profiles: ProfilesFeature()).statuses[ModulesLink.state]?()))
        #expect(!host.isEnabled(.widgets))
        #expect(host.modules[widgets]?.state == .stopped)
    }

    @Test("In the settings process the host asks the app, and lists, saves, starts and stops nothing itself")
    func settingsProcessHostAsksTheApp() async {
        // A module only this system has, which the host would list if it read the folders itself.
        _ = settingsSystem.addModule("stray")
        let widgets = URL(filePath: "/Modules/widgets.app")
        // No process has the highest pid, so no running app is let forward.
        let running = module("widgets", state: .running(.max))
        let host = settingsHost()

        host.refresh()
        #expect(requests.messages == [.command(name: ModulesLink.refresh, payload: Data())])
        #expect(host.modules.isEmpty)

        host.mirror(modules: [widgets: running], enabledIdentifiers: ["widgets"])
        await host.setEnabled(false, identifier: "widgets")
        #expect(!host.isEnabled("widgets"), "The switch shows the choice before the app answers")
        await host.setEnabled(true, identifier: "widgets")
        #expect(host.isEnabled("widgets"))
        #expect(requests.payloads(ModulesLink.Switch.self, of: ModulesLink.setEnabled) == [
            ModulesLink.Switch(identifier: "widgets", enabled: false),
            ModulesLink.Switch(identifier: "widgets", enabled: true),
        ])

        await host.start(widgets, showingWindow: true)
        await host.openWindow(of: .widgets)
        await host.start(widgets)
        await host.start(URL(filePath: "/Modules/unknown.app"), showingWindow: true)
        #expect(requests.payloads(ModulesLink.Start.self, of: ModulesLink.start) == [
            ModulesLink.Start(identifier: "widgets", showingWindow: true),
            ModulesLink.Start(identifier: "widgets", showingWindow: true),
            ModulesLink.Start(identifier: "widgets", showingWindow: false),
        ])

        host.stop(widgets)
        host.stopAll()
        await host.startAll()
        #expect(host.modules == [widgets: running], "Only the app says a module stopped")
        #expect(settingsSystem.launchesBegun == 0)
        #expect(settingsSystem.terminated.isEmpty)
        #expect(settingsSystem.savedEnabled == nil)
    }

    @Test("Opening a module that isn't running asks the app to start it with its window")
    func settingsProcessOpensAStoppedModule() async {
        let widgets = URL(filePath: "/Modules/widgets.app")
        let host = settingsHost()
        host.mirror(modules: [widgets: module("widgets", state: .gaveUp)], enabledIdentifiers: ["widgets"])
        await host.start(widgets, showingWindow: true)
        #expect(requests.payloads(ModulesLink.Start.self, of: ModulesLink.start) == [ModulesLink.Start(identifier: "widgets", showingWindow: true)])
        #expect(settingsSystem.launchesBegun == 0)
    }

    @Test("A module's row waits for the app's modules before it calls the module missing")
    func rowWaitsForTheAppsModules() async {
        let host = settingsHost()
        let size = CGSize(width: 400, height: 80)
        let row = OffscreenRender(
            ModuleControls(moduleHost: host, identifier: "widgets", name: "Widgets").frame(width: size.width, height: size.height),
            size: size
        )
        await row.settle(within: .milliseconds(300)) { !row.texts().isEmpty }
        #expect(row.texts().isEmpty, "Nothing is known about the module yet")

        host.mirror(modules: [:], enabledIdentifiers: [])
        #expect(await row.settle { row.texts().contains { $0.contains("Not installed") } })

        host.mirror(modules: [URL(filePath: "/Modules/widgets.app"): module("widgets")], enabledIdentifiers: [])
        #expect(await row.settle { row.elements().contains { OffscreenAccessibility.role(of: $0) == .checkBox } })
        #expect(!row.texts().contains { $0.contains("Not installed") })
    }

    // MARK: Profiles

    @Test("Each process follows the Profiles switch the other saved, and the app does what follows from it", .scratchDefaults)
    func profilesSwitchCrossesTheLink() {
        let inApp = ProfilesFeature()
        let inSettings = ProfilesFeature()
        var appChanges = 0
        inApp.onChange = { appChanges += 1 }
        let app = SettingsAppFeature.modules(host: appHost(), profiles: inApp)
        let child = SettingsChildFeature.modules(host: settingsHost(), profiles: inSettings)

        app.reload()
        child.reload()
        #expect(inApp.isOn && inSettings.isOn)
        #expect(appChanges == 0, "A reload for another setting changes nothing")

        inSettings.isOn = false
        app.reload()
        #expect(!inApp.isOn)
        #expect(appChanges == 1, "The app's profile shortcuts follow the switch")
        app.reload()
        #expect(appChanges == 1)

        inApp.isOn = true
        child.reload()
        #expect(inSettings.isOn)
        #expect(ProfilesFeature.isOnInDefaults)
    }

    // MARK: Where the pages run

    @Test("Modules, Widgets and Scripts run in the settings process, with their share of the link on both sides", .scratchDefaults)
    func pagesAreRegistered() {
        let panes: [SettingsNavigationIdentifier] = [.modules, .widgets, .scripts]
        #expect(SettingsProcessRoute.ownProcessPanes.isSuperset(of: panes.map(\.rawValue)))

        let appState = AppState()
        #expect(SettingsLinkFeatures.app(appState).contains { feature in
            feature.statuses[ModulesLink.state] != nil
                && [ModulesLink.refresh, ModulesLink.setEnabled, ModulesLink.start].allSatisfy { feature.commands[$0] != nil }
        })
        #expect(SettingsLinkFeatures.child(appState).contains { $0.statuses[ModulesLink.state] != nil })
    }
}
