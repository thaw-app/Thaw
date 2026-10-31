//
//  ModuleHostTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw
import ThawModuleKit

@MainActor
@Suite("Module host")
struct ModuleHostTests {
    /// A fake system: bundles in a folder, their Info.plists and team IDs,
    /// and a record of every launch, termination and wait.
    @MainActor
    final class FakeSystem {
        var bundles: [URL] = []
        var infos: [URL: [String: Any]] = [:]
        var teams: [URL: String] = [:]
        var launched: [URL] = []
        var windowsShown: [URL] = []
        var terminated: [pid_t] = []
        var waits: [TimeInterval] = []
        var failLaunch = false
        /// Launches that return no process, like an app that quits as it starts.
        var quitsAtLaunch = false
        var nextPID: pid_t = 100
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        /// Nil until the host saves a choice, like a fresh install.
        var savedEnabled: Set<String>?
        var onByDefault: Set<String> = []

        func addModule(_ name: String, team: String = "TEAM", minimumAPIVersion: Int = 1) -> URL {
            let url = URL(filePath: "/Modules/\(name).app")
            bundles.append(url)
            infos[url] = [
                "CFBundleIdentifier": "com.thaw.module.\(name)",
                "CFBundleName": "Thaw \(name.capitalized)",
                ModuleManifest.identifierKey: name,
                ModuleManifest.minimumAPIVersionKey: minimumAPIVersion,
            ]
            teams[url] = team
            return url
        }

        func environment() -> ModuleHost.Environment {
            ModuleHost.Environment(
                listBundles: { [unowned self] in bundles },
                readInfo: { [unowned self] in infos[$0] },
                teamID: { [unowned self] in teams[$0] },
                ownTeamID: { "TEAM" },
                launch: { [unowned self] url, showWindow in
                    if failLaunch {
                        throw CocoaError(.executableNotLoadable)
                    }
                    launched.append(url)
                    if showWindow {
                        windowsShown.append(url)
                    }
                    if quitsAtLaunch {
                        return -1
                    }
                    nextPID += 1
                    return nextPID
                },
                terminate: { [unowned self] in terminated.append($0) },
                now: { [unowned self] in clock },
                wait: { [unowned self] in waits.append($0) },
                loadEnabled: { [unowned self] in savedEnabled },
                saveEnabled: { [unowned self] in savedEnabled = $0 },
                enabledByDefault: { [unowned self] in onByDefault.contains($0) }
            )
        }
    }

    /// A system where every module it lists is switched on.
    private func makeHost(_ system: FakeSystem) -> ModuleHost {
        system.savedEnabled = system.savedEnabled ?? Set(system.bundles.compactMap { system.infos[$0]?[ModuleManifest.identifierKey] as? String })
        let host = ModuleHost(environment: system.environment())
        host.refresh()
        return host
    }

    @Test("Refresh lists every bundle with its launch verdict")
    func refreshListsModules() {
        let system = FakeSystem()
        let good = system.addModule("automation")
        let foreign = system.addModule("widgets", team: "OTHER")
        let host = makeHost(system)

        #expect(host.modules[good]?.verdict == .launch)
        #expect(host.modules[foreign]?.verdict == .untrusted)
        #expect(host.modules[good]?.manifest?.identifier == "automation")
    }

    @Test("A module that may not run says why before it is switched on")
    func refusedModuleShowsWhy() {
        let system = FakeSystem()
        let foreign = system.addModule("widgets", team: "OTHER")
        let newer = system.addModule("triggers", minimumAPIVersion: 99)
        let host = makeHost(system)
        #expect(host.modules[foreign]?.state == .refused(.untrusted))
        #expect(host.modules[newer]?.state == .refused(.needsNewerThaw(requiredAPIVersion: 99)))
    }

    @Test("Opening a module that isn't running launches it through the host with its window")
    func openWindowLaunchesAndTracks() async {
        let system = FakeSystem()
        let url = system.addModule("triggers")
        let host = makeHost(system)

        await host.openWindow(of: .triggers)

        #expect(system.windowsShown == [url])
        #expect(host.modules[url]?.state == .running(101), "The process is tracked, so it is restarted and its quit reported")
    }

    @Test("Refresh drops modules whose bundle is gone")
    func refreshDropsRemovedModules() {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        system.bundles = []
        host.refresh()
        #expect(host.modules[url] == nil)
    }

    @Test("Starting a trusted module launches it")
    func startLaunchesATrustedModule() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)

        await host.start(url)

        #expect(system.launched == [url])
        #expect(host.modules[url]?.state == .running(101))
    }

    @Test("Starting a refused module doesn't launch it")
    func startRefusesAnUntrustedModule() async {
        let system = FakeSystem()
        let url = system.addModule("widgets", team: "OTHER")
        let host = makeHost(system)

        await host.start(url)

        #expect(system.launched.isEmpty)
        #expect(host.modules[url]?.state == .refused(.untrusted))
    }

    @Test("A launch that throws leaves the module failed")
    func launchFailureIsRecorded() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        system.failLaunch = true
        let host = makeHost(system)

        await host.start(url)

        #expect(host.modules[url]?.state == .launchFailed)
    }

    @Test("A module that quits as it launches is failed, not running")
    func quitAtLaunchIsRecorded() async {
        let system = FakeSystem()
        let url = system.addModule("widgets")
        system.quitsAtLaunch = true
        let host = makeHost(system)

        await host.setEnabled(true, identifier: "widgets")

        #expect(host.modules[url]?.state == .launchFailed)
    }

    @Test("A module that quits on its own is restarted after the policy's delay")
    func restartsACrashedModule() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        await host.start(url)

        await host.moduleDidTerminate(pid: 101)

        #expect(system.waits == [1])
        #expect(system.launched == [url, url])
        #expect(host.modules[url]?.state == .running(102))
    }

    @Test("A module Thaw stopped is not restarted")
    func doesNotRestartAStoppedModule() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        await host.start(url)

        host.stop(url)
        await host.moduleDidTerminate(pid: 101)

        #expect(system.terminated == [101])
        #expect(system.launched == [url])
        #expect(host.modules[url]?.state == .stopped)
    }

    @Test("A module that keeps crashing is given up on")
    func givesUpAfterRepeatedCrashes() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = ModuleHost(
            environment: system.environment(),
            restartPolicy: ModuleRestartPolicy(window: 600, maxCrashes: 2, baseDelay: 1, maxDelay: 30)
        )
        host.refresh()
        await host.start(url)

        await host.moduleDidTerminate(pid: 101)
        await host.moduleDidTerminate(pid: 102)

        #expect(system.launched == [url, url])
        #expect(host.modules[url]?.state == .gaveUp)
    }

    @Test("Thaw hears when a module stops running, however it stopped")
    func reportsQuits() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        var quits: [String] = []
        host.onModuleQuit = { quits.append($0) }
        await host.start(url)

        await host.moduleDidTerminate(pid: 101)
        host.stop(url)

        #expect(quits == ["com.thaw.module.automation", "com.thaw.module.automation"])
    }

    @Test("A process Thaw didn't launch is ignored")
    func ignoresUnknownProcesses() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        await host.start(url)

        await host.moduleDidTerminate(pid: 999)

        #expect(host.modules[url]?.state == .running(101))
    }

    @Test("Stopping every module terminates only the running ones")
    func stopAllTerminatesRunningModules() async {
        let system = FakeSystem()
        let running = system.addModule("automation")
        let idle = system.addModule("widgets")
        let host = makeHost(system)
        await host.start(running)

        host.stopAll()

        #expect(system.terminated == [101])
        #expect(host.modules[running]?.state == .stopped)
        #expect(host.modules[idle]?.state == .idle)
    }

    @Test("Start all launches every module that passes and skips the rest")
    func startAllLaunchesPassingModules() async {
        let system = FakeSystem()
        let good = system.addModule("automation")
        let foreign = system.addModule("widgets", team: "OTHER")
        system.savedEnabled = ["automation", "widgets"]
        let host = ModuleHost(environment: system.environment())

        await host.startAll()

        #expect(system.launched == [good])
        #expect(host.modules[foreign]?.state == .refused(.untrusted))
    }

    @Test("Start all skips a module that is switched off")
    func startAllSkipsDisabledModules() async {
        let system = FakeSystem()
        let on = system.addModule("automation")
        _ = system.addModule("widgets")
        system.savedEnabled = ["automation"]
        let host = ModuleHost(environment: system.environment())

        await host.startAll()

        #expect(system.launched == [on])
    }

    @Test("Without a saved choice, a module starts on only when it has work from before")
    func firstRunUsesDefaults() async {
        let system = FakeSystem()
        let automation = system.addModule("automation")
        _ = system.addModule("widgets")
        system.onByDefault = ["automation"]
        let host = ModuleHost(environment: system.environment())

        await host.startAll()

        #expect(system.launched == [automation])
        #expect(system.savedEnabled == ["automation"])
        #expect(host.isEnabled("automation"))
        #expect(!host.isEnabled("widgets"))
    }

    @Test("A saved choice is known before the first scan")
    func savedChoiceIsReadAtOnce() {
        let system = FakeSystem()
        system.savedEnabled = ["widgets"]
        let host = ModuleHost(environment: system.environment())
        #expect(host.isEnabled("widgets"))
        #expect(!host.isEnabled("automation"))
    }

    @Test("A saved choice wins over the default")
    func savedChoiceWins() async {
        let system = FakeSystem()
        _ = system.addModule("automation")
        system.onByDefault = ["automation"]
        system.savedEnabled = []
        let host = ModuleHost(environment: system.environment())

        await host.startAll()

        #expect(system.launched.isEmpty)
    }

    @Test("Switching a module on launches it and saves the choice")
    func switchingOnLaunches() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        system.savedEnabled = []
        let host = ModuleHost(environment: system.environment())
        host.refresh()

        await host.setEnabled(true, identifier: "automation")

        #expect(system.launched == [url])
        #expect(system.savedEnabled == ["automation"])
    }

    @Test("Switching a module off stops it and saves the choice")
    func switchingOffStops() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        await host.start(url)

        await host.setEnabled(false, identifier: "automation")

        #expect(system.terminated == [101])
        #expect(system.savedEnabled == [])
        #expect(host.modules[url]?.state == .stopped)
    }

    @Test("Start all leaves a running module alone")
    func startAllSkipsRunningModules() async {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        await host.start(url)

        await host.startAll()

        #expect(system.launched == [url])
    }

    @Test("A downloaded module replaces a bundled one with the same identifier")
    func downloadedCopyWins() {
        let system = FakeSystem()
        let downloaded = system.addModule("automation")
        let bundled = URL(filePath: "/Thaw.app/Contents/Library/Modules/automation.app")
        system.bundles.append(bundled)
        system.infos[bundled] = system.infos[downloaded]
        system.teams[bundled] = "TEAM"
        let host = makeHost(system)

        #expect(host.modules[downloaded] != nil)
        #expect(host.modules[bundled] == nil)
    }

    @Test("A module is found by its identifier")
    func findsAModuleByIdentifier() {
        let system = FakeSystem()
        let url = system.addModule("automation")
        let host = makeHost(system)
        #expect(host.url(ofModule: "automation") == url)
        #expect(host.url(ofModule: "widgets") == nil)
    }

    @Test("Modules shipped inside Thaw sit in Contents/Library/Modules")
    func bundledModulesDirectoryLocation() {
        let directory = ModuleHost.bundledModulesDirectory(appBundle: URL(filePath: "/Applications/Thaw.app"))
        #expect(directory.path == "/Applications/Thaw.app/Contents/Library/Modules")
    }

    @Test("The modules folder sits in Thaw's Application Support folder")
    func modulesDirectoryLocation() {
        let support = URL(filePath: "/Users/test/Library/Application Support")
        let directory = ModuleHost.modulesDirectory(applicationSupport: support)
        #expect(directory.path == "/Users/test/Library/Application Support/\(ThawMenuBarIdentity.bundleIdentifier)/Modules")
    }
}
