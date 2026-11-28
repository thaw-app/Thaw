//
//  RunningApplicationsWatch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Apps that start and quit, read from `runningApplications`. NSWorkspace's launch and
/// termination notifications skip apps without a Dock icon, which most menu bar apps are.
@MainActor
final class RunningApplicationsWatch {
    struct Change {
        var launched: [NSRunningApplication]
        var terminated: [NSRunningApplication]
    }

    private var known: [pid_t: NSRunningApplication]
    private var observation: NSKeyValueObservation?
    /// Copies started beside an app already running. They own no items and usually quit at once.
    private var secondCopies = Set<pid_t>()

    private let onChange: @MainActor (Change) -> Void

    init(onChange: @escaping @MainActor (Change) -> Void) {
        self.onChange = onChange
        known = Self.byPID(NSWorkspace.shared.runningApplications)
        observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.readRunningApplications() }
        }
    }

    private func readRunningApplications() {
        let running = Self.byPID(NSWorkspace.shared.runningApplications)
        let (launched, terminated) = Self.difference(from: Set(known.keys), to: Set(running.keys))
        let stillRunning = known.filter { running[$0.key] != nil }
        let copies = Self.secondCopies(
            launched: launched.reduce(into: [pid_t: String]()) { $0[$1] = running[$1]?.bundleIdentifier },
            alreadyRunning: Set(stillRunning.values.compactMap(\.bundleIdentifier))
        )
        secondCopies.formUnion(copies)
        let change = Change(
            launched: launched.filter { !copies.contains($0) }.compactMap { running[$0] },
            terminated: terminated.filter { !secondCopies.contains($0) }.compactMap { known[$0] }
        )
        secondCopies.subtract(terminated)
        known = running
        if !change.launched.isEmpty || !change.terminated.isEmpty {
            onChange(change)
        }
    }

    nonisolated static func difference(from known: Set<pid_t>, to running: Set<pid_t>) -> (launched: [pid_t], terminated: [pid_t]) {
        (running.subtracting(known).sorted(), known.subtracting(running).sorted())
    }

    /// Launched processes of an app that was already running under another process.
    nonisolated static func secondCopies(launched: [pid_t: String], alreadyRunning: Set<String>) -> Set<pid_t> {
        Set(launched.filter { alreadyRunning.contains($0.value) }.keys)
    }

    private static func byPID(_ apps: [NSRunningApplication]) -> [pid_t: NSRunningApplication] {
        Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}
