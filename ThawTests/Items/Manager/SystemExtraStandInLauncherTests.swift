//
//  SystemExtraStandInLauncherTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw

@MainActor
@Suite("Stand-in launcher")
struct SystemExtraStandInLauncherTests {
    private let fake = FakeStandInSystem()
    private let sections = FakeStandInSections()
    private let original = "com.apple.menuextra.timer"

    private func makeLauncher() -> (SystemExtraStandInLauncher, Box) {
        let launcher = SystemExtraStandInLauncher(system: fake.system)
        let known = Box()
        launcher.controller = sections
        launcher.markKnown = { known.identifiers.append($0) }
        return (launcher, known)
    }

    final class Box {
        var identifiers: [String] = []
    }

    private func id(_ standIn: SystemExtraStandIn) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(standIn.itemIdentifier)
    }

    @Test("A missing bundle throws before anything is recorded or opened")
    func missingBundleThrows() async {
        fake.missingBundles = [SystemExtraStandIn.timer.bundleURL]
        let (launcher, known) = makeLauncher()

        await #expect(throws: SystemExtraTakeoverError.replacementUnavailable) {
            try await launcher.launch(.timer, replacing: original, in: .hidden)
        }
        #expect(known.identifiers.isEmpty)
        #expect(fake.opens.isEmpty)
        #expect(sections.writes.isEmpty)
        #expect(launcher.wanted.isEmpty)
        #expect(launcher.placed.isEmpty)
    }

    @Test("A launch marks the stand-in known, gives it the section and the original's slot, then opens it quietly")
    func launchPlacesThenOpens() async throws {
        sections.sectionItemOrder[.hidden] = ["a", original, "b"]
        let (launcher, known) = makeLauncher()

        try await launcher.launch(.timer, replacing: original, in: .hidden)

        #expect(known.identifiers == [id(.timer)])
        #expect(sections.writes == [
            .section(.hidden, id(.timer)),
            .order(["a", original, id(.timer), "b"], .hidden),
        ])
        let open = try #require(fake.opens.only)
        #expect(open.url == SystemExtraStandIn.timer.bundleURL)
        #expect(!open.activates)
        #expect(!open.addsToRecentItems)
        #expect(!open.promptsUserIfNeeded)
        #expect(open.arguments == ["--parent-pid", String(ProcessInfo.processInfo.processIdentifier)])
        #expect(launcher.wanted == [.timer])
        #expect(launcher.placed == [.timer])
        #expect(try #require(fake.startedProcesses.only).isWatched)
    }

    @Test("A stand-in already in the section keeps its assignment and a placed one keeps its slot")
    func launchKeepsExistingPlacement() async throws {
        sections.sectionAssignment[id(.timer)] = .hidden
        sections.sectionItemOrder[.hidden] = [id(.timer), original]
        let (launcher, _) = makeLauncher()

        try await launcher.launch(.timer, replacing: original, in: .hidden)

        #expect(sections.writes.isEmpty)
        #expect(launcher.placed == [.timer])
    }

    @Test("An instance still running is adopted instead of opening another; a dead one is passed over")
    func runningInstanceIsAdopted() async throws {
        let dead = FakeStandInProcess(pid: 11, isTerminated: true)
        let alive = FakeStandInProcess(pid: 12)
        fake.running[SystemExtraStandIn.focus.bundleIdentifier] = [dead, alive]
        let (launcher, _) = makeLauncher()

        try await launcher.launch(.focus, replacing: original, in: .visible)

        #expect(fake.opens.isEmpty)
        #expect(alive.isWatched)
        #expect(!dead.isWatched)
    }

    @Test("Stopping forgets the stand-in, stops watching it and quits every running instance")
    func stopQuitsEverything() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        let started = try #require(fake.startedProcesses.only)
        let other = FakeStandInProcess(pid: 99)
        fake.running[SystemExtraStandIn.timer.bundleIdentifier] = [other]

        launcher.stop(.timer)

        #expect(launcher.wanted.isEmpty)
        #expect(launcher.placed.isEmpty)
        #expect(started.watchStops == 1)
        #expect(started.terminateCalls == 1)
        #expect(other.terminateCalls == 1)
        started.exit()
        await settle { fake.opens.count > 1 }
        #expect(fake.opens.count == 1)
    }

    @Test("A stand-in turned off while it was opening is quit and not watched")
    func turnedOffDuringOpenIsQuit() async throws {
        let (launcher, _) = makeLauncher()
        fake.duringOpen = { launcher.stop(.timer) }

        try await launcher.launch(.timer, replacing: original, in: .hidden)

        let started = try #require(fake.startedProcesses.only)
        #expect(started.terminateCalls == 1)
        #expect(!started.isWatched)
    }

    @Test("An open that fails is passed on to the caller")
    func failedOpenThrows() async {
        struct OpenFailed: Error {}
        fake.openError = OpenFailed()
        let (launcher, _) = makeLauncher()

        await #expect(throws: OpenFailed.self) {
            try await launcher.launch(.timer, replacing: original, in: .hidden)
        }
    }

    @Test("A stand-in that exits on its own is started again")
    func exitedStandInRestarts() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        let first = try #require(fake.startedProcesses.only)

        first.exit()
        await settle { fake.startedProcesses.count == 2 }

        #expect(fake.opens.count == 2)
        #expect(first.watchStops == 1)
        #expect(fake.startedProcesses.last?.isWatched == true)
    }

    @Test("A late exit from a stopped stand-in starts nothing")
    func lateExitAfterStopIsIgnored() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        let first = try #require(fake.startedProcesses.only)
        launcher.stop(.timer)

        first.lateExit()
        await settle { fake.opens.count > 1 }

        #expect(fake.opens.count == 1)
    }

    @Test("A late exit from a replaced process leaves its successor alone")
    func lateExitFromReplacedProcessIsIgnored() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        let first = try #require(fake.startedProcesses.only)
        await launcher.restartRunning()
        let second = try #require(fake.startedProcesses.last)

        first.lateExit()
        await settle { fake.opens.count > 2 }

        #expect(fake.opens.count == 2)
        #expect(second.isWatched)
        #expect(second.watchStops == 0)
    }

    @Test("A stand-in that keeps exiting is started again three times, then left down")
    func restartsAreLimited() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)

        for expected in 2 ... 4 {
            try #require(fake.startedProcesses.last).exit()
            await settle { fake.startedProcesses.count == expected }
            #expect(fake.startedProcesses.count == expected)
        }
        try #require(fake.startedProcesses.last).exit()
        await settle { fake.startedProcesses.count == 5 }

        #expect(fake.startedProcesses.count == 4)
    }

    @Test("A stand-in that is already gone when opened is started again")
    func alreadyExitedIsRestarted() async throws {
        fake.nextStartsTerminated = true
        let (launcher, _) = makeLauncher()

        try await launcher.launch(.timer, replacing: original, in: .hidden)
        await settle { fake.opens.count == 2 }

        #expect(fake.opens.count == 2)
        #expect(fake.startedProcesses.first?.watchStops == 1)
        #expect(fake.startedProcesses.last?.isWatched == true)
    }

    @Test("Restarting quits each running stand-in and opens it again")
    func restartRunningReopens() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        try await launcher.launch(.focus, replacing: original, in: .hidden)
        let first = fake.startedProcesses

        await launcher.restartRunning()

        for process in first {
            #expect(process.terminateCalls == 1)
            #expect(process.forceTerminateCalls == 0)
            #expect(process.watchStops == 1)
        }
        #expect(fake.opened(.timer) == 2)
        #expect(fake.opened(.focus) == 2)
        let watched = fake.startedProcesses.suffix(2).map(\.isWatched)
        #expect(watched == [true, true])
    }

    @Test("A stand-in that ignores the quit is forced to quit before it is opened again")
    func restartForcesAHungStandIn() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        let hung = try #require(fake.startedProcesses.only)
        hung.quitsOnTerminate = false

        await launcher.restartRunning()

        #expect(hung.forceTerminateCalls == 1)
        #expect(fake.opens.count == 2)
    }

    @Test("A restart whose open fails leaves the stand-in unwatched")
    func failedRestartLeavesItDown() async throws {
        struct OpenFailed: Error {}
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        fake.openError = OpenFailed()

        await launcher.restartRunning()
        await launcher.restartRunning()

        #expect(fake.opens.count == 2)
    }

    @Test("The engine's publish and remove reach the item's own stand-in")
    func publishAndRemoveMapItems() async throws {
        let (launcher, _) = makeLauncher()

        try await launcher.publish(item: .textInput, canonicalIdentifier: original, section: .alwaysHidden)

        #expect(fake.opened(.textInput) == 1)
        #expect(sections.writes.first == .section(.alwaysHidden, id(.textInput)))
        launcher.remove(item: .textInput)
        #expect(launcher.wanted.isEmpty)
        #expect(fake.startedProcesses.only?.terminateCalls == 1)
        #expect(fake.startedProcesses.only?.watchStops == 1)
    }

    @Test("The system seam finds bundles on disk and lists this process among running apps")
    func systemSeamReadsTheSystem() throws {
        let system = StandInSystem()
        let bundle = Bundle.main.bundleURL
        let identifier = try #require(Bundle.main.bundleIdentifier)

        #expect(system.bundleExists(bundle))
        #expect(!system.bundleExists(bundle.appending(path: "Contents/Library/Extras/Missing.app")))
        #expect(system.running(identifier).contains { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier })
        #expect(system.running("com.example.thaw.tests.none").isEmpty)
    }

    @Test("The spacing relaunch reaches the launcher the coordinator registered")
    func spacingRestartReachesLauncher() async throws {
        let (launcher, _) = makeLauncher()
        try await launcher.launch(.timer, replacing: original, in: .hidden)
        let previous = StandInSpacingRestart.launcher
        StandInSpacingRestart.launcher = launcher
        defer { StandInSpacingRestart.launcher = previous }

        await StandInSpacingRestart.run()

        #expect(fake.opens.count == 2)
    }
}

extension Collection {
    /// The single element, or nil when there are none or several.
    var only: Element? {
        count == 1 ? first : nil
    }
}
