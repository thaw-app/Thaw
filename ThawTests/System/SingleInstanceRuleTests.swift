//
//  SingleInstanceRuleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The rule that keeps a second copy of Thaw from launching unnoticed.
@Suite("Single instance rule")
struct SingleInstanceRuleTests {
    private typealias Rule = SingleInstanceRule
    private typealias Process = SingleInstanceRule.RunningProcess

    private static let ownPID: pid_t = 500

    private func process(
        _ bundle: String?,
        pid: pid_t,
        parent: pid_t? = 1,
        name: String? = nil,
        terminated: Bool = false
    ) -> Process {
        Process(
            processIdentifier: pid,
            parentProcessIdentifier: parent,
            bundleIdentifier: bundle,
            localizedName: name,
            isTerminated: terminated
        )
    }

    private func decide(
        _ running: [Process],
        bundle: String? = "com.stonerl.Thaw",
        mode: Rule.LaunchMode = .app,
        lock: Rule.LockState = .acquired,
        relaunchedFrom: pid_t? = nil
    ) -> Rule.Decision {
        Rule.decide(
            ownProcessIdentifier: Self.ownPID,
            ownBundleIdentifier: bundle,
            launchMode: mode,
            lock: lock,
            relaunchedFrom: relaunchedFrom,
            running: running
        )
    }

    private func ask(_ others: [Process], lockHeldElsewhere: Bool = false) -> Rule.Decision {
        .ask(others: others, lockHeldElsewhere: lockHeldElsewhere)
    }

    private var ownProcess: Process {
        process("com.stonerl.Thaw", pid: Self.ownPID, name: "Thaw")
    }

    @Test("The main app of every build counts, its parts and helpers do not")
    func thawAppBundles() {
        #expect(Rule.isThawApp(bundleIdentifier: "com.stonerl.Thaw"))
        #expect(Rule.isThawApp(bundleIdentifier: "com.stonerl.Thaw.debug"))
        #expect(Rule.isThawApp(bundleIdentifier: "com.example.fork", ownBundleIdentifier: "com.example.fork"))
        for part in [
            "com.stonerl.Thaw.MenuBarCaptureService",
            "com.stonerl.Thaw.debug.MenuBarCaptureService",
            "com.stonerl.Thaw.ThawControls",
            "com.stonerl.Thaw.debug.ThawControls",
            "com.stonerl.Thaw.tests",
            "com.stonerl.Thaw.extra.timemachine",
            "com.stonerl.Thaw.debug.extra.focus",
            "com.stonerl.Thaw.",
            "com.stonerl.Thawed",
            "com.surteesstudios.Bartender",
        ] {
            #expect(!Rule.isThawApp(bundleIdentifier: part), "\(part)")
        }
        #expect(!Rule.isThawApp(bundleIdentifier: nil))
    }

    @Test("Launch goes on when no other copy runs")
    func noOtherCopy() {
        let decision = decide([
            ownProcess,
            process("com.apple.finder", pid: 10, name: "Finder"),
            process(nil, pid: 11),
        ])
        #expect(decision == .proceed)
    }

    @Test("A release copy and a debug copy each count, from either side")
    func releaseAndDebugCopies() {
        let release = process("com.stonerl.Thaw", pid: 20, name: "Thaw")
        let debug = process("com.stonerl.Thaw.debug", pid: 21, name: "Thaw Debug")
        #expect(decide([ownProcess, debug]) == ask([debug]))
        #expect(decide([release], bundle: "com.stonerl.Thaw.debug") == ask([release]))
        #expect(decide([release, debug]) == ask([release, debug]))
    }

    @Test("A second copy of the same build counts")
    func sameBuildTwice() {
        let twin = process("com.stonerl.Thaw", pid: 30, name: "Thaw")
        #expect(decide([ownProcess, twin]) == ask([twin]))
    }

    @Test("This copy's own Settings process is not another copy")
    func ownSettingsChild() {
        let settings = process("com.stonerl.Thaw", pid: 40, parent: Self.ownPID, name: "Thaw")
        #expect(decide([ownProcess, settings]) == .proceed)
    }

    @Test("Another copy's Settings process is listed through its parent only")
    func otherCopysSettingsChild() {
        let other = process("com.stonerl.Thaw.debug", pid: 41, name: "Thaw Debug")
        let settings = process("com.stonerl.Thaw.debug", pid: 42, parent: 41, name: "Thaw Debug")
        #expect(decide([ownProcess, other, settings]) == ask([other]))
    }

    @Test("The Settings process skips the check, but a normal launch counts the copy that started it")
    func settingsProcessSeesItsParent() {
        let parent = process("com.stonerl.Thaw", pid: 50, name: "Thaw")
        #expect(decide([parent], mode: .settingsProcess, lock: .heldElsewhere) == .proceed)
        #expect(decide([parent]) == ask([parent]))
    }

    @Test("A lock held by another process means another copy runs, even when no app shows it")
    func lockHeldElsewhere() {
        #expect(decide([ownProcess], lock: .heldElsewhere) == ask([], lockHeldElsewhere: true))
        let other = process("com.stonerl.Thaw.debug", pid: 55, name: "Thaw Debug")
        #expect(decide([ownProcess, other], lock: .heldElsewhere) == ask([other], lockHeldElsewhere: true))
    }

    @Test("Without the lock file, the running apps alone decide")
    func lockUnavailable() {
        let other = process("com.stonerl.Thaw.debug", pid: 56, name: "Thaw Debug")
        #expect(decide([ownProcess], lock: .unavailable) == .proceed)
        #expect(decide([ownProcess, other], lock: .unavailable) == ask([other]))
    }

    @Test("A copy found among the running apps counts even when this launch took the lock")
    func copyWithoutLock() {
        let older = process("com.stonerl.Thaw", pid: 57, name: "Thaw")
        #expect(decide([ownProcess, older], lock: .acquired) == ask([older]))
    }

    @Test("A restart does not count the copy it replaces, or that copy's children")
    func relaunchOfSelf() {
        let old = process("com.stonerl.Thaw", pid: 60, name: "Thaw")
        let oldSettings = process("com.stonerl.Thaw", pid: 61, parent: 60, name: "Thaw")
        #expect(decide([ownProcess, old, oldSettings], relaunchedFrom: 60) == .proceed)
        #expect(decide([ownProcess, old], relaunchedFrom: 99) == ask([old]))
    }

    @Test("Processes that already quit are ignored")
    func terminatedIgnored() {
        let gone = process("com.stonerl.Thaw.debug", pid: 70, name: "Thaw Debug", terminated: true)
        #expect(decide([ownProcess, gone]) == .proceed)
    }

    @Test("The capture service, the controls extension, helpers and the test bundle are ignored")
    func partsIgnored() {
        let decision = decide([
            ownProcess,
            process("com.stonerl.Thaw.MenuBarCaptureService", pid: 80),
            process("com.stonerl.Thaw.ThawControls", pid: 81),
            process("com.stonerl.Thaw.extra.timemachine", pid: 82),
            process("com.stonerl.Thaw.tests", pid: 83),
        ])
        #expect(decision == .proceed)
    }

    @Test("Only a normal app launch checks")
    func otherLaunchModesSkip() {
        let other = process("com.stonerl.Thaw.debug", pid: 90, name: "Thaw Debug")
        for mode in [Rule.LaunchMode.testHost, .settingsProcess, .visibilityRecovery] {
            #expect(decide([other], mode: mode, lock: .heldElsewhere) == .proceed, "\(mode)")
        }
    }

    @Test("The prompt names one copy, several copies, or none")
    func wording() {
        let release = process("com.stonerl.Thaw", pid: 91, name: "Thaw")
        let debug = process("com.stonerl.Thaw.debug", pid: 92, name: "Thaw Debug")
        let twin = process("com.stonerl.Thaw", pid: 93, name: "Thaw")
        #expect(Rule.Wording([]) == .unnamed)
        #expect(Rule.Wording([debug]) == .one("Thaw Debug"))
        #expect(Rule.Wording([release, twin]) == .one("Thaw"), "Two copies with one name read as one")
        #expect(Rule.Wording([release, debug]) == .several(["Thaw", "Thaw Debug"]))
    }

    @Test("The launch mode comes from the environment and arguments")
    func launchModes() {
        let app = "/Applications/Thaw.app/Contents/MacOS/Thaw"
        #expect(Rule.launchMode(arguments: [app], environment: [:]) == .app)
        #expect(Rule.launchMode(arguments: [app], environment: ["XCTestConfigurationFilePath": "/x"]) == .testHost)
        #expect(Rule.launchMode(arguments: [app], environment: ["XCTestSessionIdentifier": "1"]) == .testHost)
        #expect(Rule.launchMode(arguments: [app, "--settings", "General"], environment: [:]) == .settingsProcess)
        #expect(Rule.launchMode(arguments: [app, "--recover-menu-bar-visibility"], environment: [:]) == .visibilityRecovery)
        #expect(Rule.launchMode(arguments: [app, "--settings", "General"], environment: ["XCTestBundlePath": "/x"]) == .testHost)
    }

    @Test("The test host is recognized")
    func liveTestHosting() {
        let info = ProcessInfo.processInfo
        #expect(Rule.launchMode(arguments: info.arguments, environment: info.environment) == .testHost)
    }

    @Test("The replaced process travels in the launch arguments")
    func relaunchArguments() {
        let arguments = ["Thaw"] + Rule.relaunchArguments(replacing: 4321)
        #expect(Rule.relaunchedFrom(arguments: arguments) == 4321)
        #expect(Rule.relaunchedFrom(arguments: ["Thaw"]) == nil)
        #expect(Rule.relaunchedFrom(arguments: ["Thaw", "--relaunched-from"]) == nil)
        #expect(Rule.relaunchedFrom(arguments: ["Thaw", "--relaunched-from", "x"]) == nil)
    }

    @Test("A process without a name is shown by its bundle identifier")
    func displayNames() {
        #expect(process("com.stonerl.Thaw.debug", pid: 1, name: "Thaw Debug").displayName == "Thaw Debug")
        #expect(process("com.stonerl.Thaw.debug", pid: 1).displayName == "com.stonerl.Thaw.debug")
        #expect(process(nil, pid: 7).displayName == "7")
    }

    @Test("The kernel reports this process's parent and that it is running")
    func processTable() {
        let entry = ProcessTable.entry(for: getpid())
        #expect(entry?.parentProcessIdentifier == getppid())
        #expect(entry?.isZombie == false)
        #expect(ProcessTable.isRunning(getpid()))
        #expect(!ProcessTable.isRunning(pid_t.max))
    }
}
