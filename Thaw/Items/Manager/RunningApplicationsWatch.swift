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

    init(onChange: @escaping @MainActor (Change) -> Void) {
        known = Self.byPID(NSWorkspace.shared.runningApplications)
        observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let running = Self.byPID(NSWorkspace.shared.runningApplications)
                let (launched, terminated) = Self.difference(from: Set(known.keys), to: Set(running.keys))
                let change = Change(
                    launched: launched.compactMap { running[$0] },
                    terminated: terminated.compactMap { known[$0] }
                )
                known = running
                if !change.launched.isEmpty || !change.terminated.isEmpty {
                    onChange(change)
                }
            }
        }
    }

    nonisolated static func difference(from known: Set<pid_t>, to running: Set<pid_t>) -> (launched: [pid_t], terminated: [pid_t]) {
        (running.subtracting(known).sorted(), known.subtracting(running).sorted())
    }

    private static func byPID(_ apps: [NSRunningApplication]) -> [pid_t: NSRunningApplication] {
        Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}
