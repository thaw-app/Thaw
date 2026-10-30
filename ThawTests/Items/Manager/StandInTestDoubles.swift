//
//  StandInTestDoubles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import PlatformRuntimeKit
@testable import Thaw

/// An in-memory section layout that records every write.
@MainActor
final class FakeStandInSections: StandInSectionControlling {
    enum Write: Equatable {
        case section(MenuBarSectionName, String)
        case order([String], MenuBarSectionName)
    }

    var sectionAssignment: [String: MenuBarSectionName] = [:]
    var sectionItemOrder: [MenuBarSectionName: [String]] = [:]
    private(set) var writes: [Write] = []
    private let changes = PassthroughSubject<Void, Never>()

    var layoutChanges: AnyPublisher<Void, Never> {
        changes.eraseToAnyPublisher()
    }

    func authoredSection(for identifier: String) -> MenuBarSectionName {
        sectionAssignment[identifier] ?? .visible
    }

    func setSection(_ section: MenuBarSectionName, identifier: String) {
        writes.append(.section(section, identifier))
        sectionAssignment[identifier] = section
    }

    func setSectionOrder(_ identifiers: [String], for section: MenuBarSectionName) {
        writes.append(.order(identifiers, section))
        sectionItemOrder[section] = identifiers
    }

    /// Announces a layout change the way the controller's publishers do.
    func announce() {
        changes.send()
    }
}

/// A stand-in process that never existed outside this test.
@MainActor
final class FakeStandInProcess: StandInProcess {
    let processIdentifier: pid_t
    var isTerminated: Bool
    /// When false, terminate is ignored the way a hung app ignores it.
    var quitsOnTerminate = true
    private(set) var terminateCalls = 0
    private(set) var forceTerminateCalls = 0
    private(set) var watchStops = 0
    private var exited: (@Sendable (pid_t) -> Void)?
    private var lastHandler: (@Sendable (pid_t) -> Void)?

    init(pid: pid_t, isTerminated: Bool = false) {
        processIdentifier = pid
        self.isTerminated = isTerminated
    }

    var isWatched: Bool {
        exited != nil
    }

    func terminate() -> Bool {
        terminateCalls += 1
        if quitsOnTerminate {
            isTerminated = true
        }
        return true
    }

    func forceTerminate() -> Bool {
        forceTerminateCalls += 1
        isTerminated = true
        return true
    }

    func watchTermination(_ exited: @escaping @Sendable (pid_t) -> Void) -> () -> Void {
        self.exited = exited
        lastHandler = exited
        return { [weak self] in
            self?.watchStops += 1
            self?.exited = nil
        }
    }

    /// Ends the process on its own, as a crash or a quit from elsewhere would.
    func exit() {
        isTerminated = true
        exited?(processIdentifier)
    }

    /// Delivers an exit through a watch already stopped, as a callback queued before the stop would.
    func lateExit() {
        isTerminated = true
        lastHandler?(processIdentifier)
    }
}

/// The system as the launcher sees it: bundles that exist, apps that run, and every open asked for.
@MainActor
final class FakeStandInSystem {
    struct Open {
        let url: URL
        let activates: Bool
        let addsToRecentItems: Bool
        let promptsUserIfNeeded: Bool
        let arguments: [String]
    }

    var missingBundles: Set<URL> = []
    /// Instances running from before, by bundle identifier; opened ones are added on their own.
    var running: [String: [FakeStandInProcess]] = [:]
    /// Makes the next opened process report itself already ended.
    var nextStartsTerminated = false
    private(set) var opens: [Open] = []
    /// Runs inside an open before it returns, standing in for the wait on the system.
    var duringOpen: (() -> Void)?
    var openError: (any Error)?
    private var nextPID: pid_t = 70000

    /// Every process an open started, newest last.
    private(set) var started: [(url: URL, process: FakeStandInProcess)] = []

    var startedProcesses: [FakeStandInProcess] {
        started.map(\.process)
    }

    var system: StandInSystem {
        StandInSystem(
            bundleExists: { [unowned self] in !missingBundles.contains($0) },
            running: { [unowned self] bundleID in
                let url = SystemExtraStandIn.allCases.first { $0.bundleIdentifier == bundleID }?.bundleURL
                return (running[bundleID] ?? []) + started.filter { $0.url == url }.map(\.process)
            },
            open: { [unowned self] url, configuration in
                opens.append(Open(
                    url: url,
                    activates: configuration.activates,
                    addsToRecentItems: configuration.addsToRecentItems,
                    promptsUserIfNeeded: configuration.promptsUserIfNeeded,
                    arguments: configuration.arguments
                ))
                duringOpen?()
                if let openError {
                    throw openError
                }
                nextPID += 1
                let process = FakeStandInProcess(pid: nextPID, isTerminated: nextStartsTerminated)
                nextStartsTerminated = false
                started.append((url, process))
                return process
            }
        )
    }

    func opened(_ standIn: SystemExtraStandIn) -> Int {
        opens.count(where: { $0.url == standIn.bundleURL })
    }
}

/// A native switch that only remembers what it was set to.
@MainActor
final class FakeNativeSwitch: SystemExtraNativeControlling {
    let item: SystemExtraItem
    var capability: SystemExtraTakeoverCapability = .supported
    var value: SystemExtraOriginalValue
    private(set) var writes: [SystemExtraOriginalValue] = []
    private(set) var hides = 0

    init(item: SystemExtraItem, value: SystemExtraOriginalValue = .value(1)) {
        self.item = item
        self.value = value
    }

    var hiddenValue: SystemExtraOriginalValue {
        .value(0)
    }

    func readOriginal() throws -> SystemExtraOriginalValue {
        value
    }

    func write(_ value: SystemExtraOriginalValue) throws {
        writes.append(value)
        self.value = value
    }

    func hideOriginal() async throws {
        hides += 1
        try write(hiddenValue)
    }
}

/// A journal kept in memory.
@MainActor
final class MemoryExtraJournal: SystemExtraOriginalJournaling {
    var entries: [String: SystemExtraOriginalValue] = [:]

    func load() throws -> [String: SystemExtraOriginalValue] {
        entries
    }

    func save(_ entries: [String: SystemExtraOriginalValue]) throws {
        self.entries = entries
    }
}

/// Polls until condition holds or about two seconds pass; the caller's expectations report a timeout.
@MainActor
func settle(until condition: () -> Bool) async {
    var tries = 0
    while !condition(), tries < 400 {
        tries += 1
        try? await Task.sleep(for: .milliseconds(5))
    }
}
