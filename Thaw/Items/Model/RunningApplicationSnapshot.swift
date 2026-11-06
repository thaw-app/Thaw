//
//  RunningApplicationSnapshot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

nonisolated struct RunningApplicationSnapshot: Sendable, Equatable {
    let processIDs: Set<pid_t>
    let bundleIdentifiers: Set<String>
    /// Each running process's bundle, for callers that need to know which app a process is.
    let bundleIdentifiersByPID: [pid_t: String]

    init(processIDs: Set<pid_t>, bundleIdentifiers: Set<String>, bundleIdentifiersByPID: [pid_t: String] = [:]) {
        self.processIDs = processIDs
        self.bundleIdentifiers = bundleIdentifiers
        self.bundleIdentifiersByPID = bundleIdentifiersByPID
    }

    @concurrent
    static func current(
        collect: @Sendable () -> Self = readSystem
    ) async -> Self {
        collect()
    }

    /// The process table as it is now, read on the caller's thread. For a caller that cannot wait.
    static func readSystem() -> Self {
        let applications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        return Self(
            processIDs: Set(applications.map(\.processIdentifier)),
            bundleIdentifiers: Set(applications.compactMap(\.bundleIdentifier)),
            bundleIdentifiersByPID: Dictionary(
                applications.compactMap { app in app.bundleIdentifier.map { (app.processIdentifier, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}
