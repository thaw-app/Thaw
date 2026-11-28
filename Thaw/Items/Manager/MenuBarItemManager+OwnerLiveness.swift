//
//  MenuBarItemManager+OwnerLiveness.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// What the periodic liveness check remembers between ticks.
struct OwnerPurgeState {
    /// Whether a read of the process table is in flight.
    var isRunning = false
    var gate = OwnerLivenessGate<Set<ObjectIdentifier>>()
    /// The processes the last read found, with each one's app, or nil before the first read.
    private(set) var runningProcesses: [pid_t: String]?
    /// Processes launch notices reported since the last read, with each one's app.
    private var announcedLaunches: [pid_t: String] = [:]

    /// Records the processes a read found and returns the apps running a process the previous
    /// read didn't list, so an app that quit and reopened between two reads counts too. Leaves
    /// out processes a launch notice reported, and returns none for the first read.
    ///
    /// A launch noted while the read was in flight stays known, since the read can predate it.
    mutating func noteRunning(_ processes: [pid_t: String]) -> Set<String> {
        let previous = runningProcesses
        let announced = announcedLaunches
        runningProcesses = processes.merging(announced) { listed, _ in listed }
        announcedLaunches = [:]
        guard let previous else { return [] }
        return Set(processes.compactMap { pid, bundleID in
            previous[pid] == bundleID || announced[pid] == bundleID ? nil : bundleID
        })
    }

    /// Counts a process a launch notice reported, so the next read doesn't report its app again.
    mutating func noteLaunched(_ bundleID: String, processIdentifier: pid_t) {
        announcedLaunches[processIdentifier] = bundleID
    }
}

/// The cheap questions the liveness check asks before it reads the process table.
struct OwnerLivenessProbe {
    /// Whether a process with this ID exists. Asks the kernel only.
    var isAlive: (pid_t) -> Bool
    /// What identifies the current list of running apps, without asking about any of them.
    var runningApplications: @MainActor () -> Set<ObjectIdentifier>

    static let live = OwnerLivenessProbe(
        // EPERM means the process exists and belongs to someone else.
        isAlive: { kill($0, 0) == 0 || errno == EPERM },
        runningApplications: { Set(NSWorkspace.shared.runningApplications.map(ObjectIdentifier.init)) }
    )
}

extension MenuBarItemManager {
    var isPurgingDepartedOwners: Bool {
        get { ownerPurge.isRunning }
        set { ownerPurge.isRunning = newValue }
    }

    /// Purge before the periodic window-list gate: macOS 27 can omit terminate notifications, and AX-only items own no window.
    /// Read LaunchServices-backed owner properties off MainActor and skip the purge if the cache changes during the read.
    /// Returns the process table it read, or nil when it read none or was cancelled.
    @discardableResult
    func purgeDepartedOwners(
        readOwners: @Sendable () async -> RunningApplicationSnapshot = { await RunningApplicationSnapshot.current() }
    ) async -> RunningApplicationSnapshot? {
        guard !isPurgingDepartedOwners, !Task.isCancelled else { return nil }
        isPurgingDepartedOwners = true
        defer { isPurgingDepartedOwners = false }
        let cacheAtStart = itemCache
        let owners = await readOwners()
        guard !Task.isCancelled else { return nil }
        if itemCache == cacheAtStart {
            purgeDepartedOwners(
                processIDs: owners.processIDs,
                bundleIdentifiers: owners.bundleIdentifiers
            )
        }
        return owners
    }

    /// The tick's liveness check: purgeDepartedOwners(readOwners:), skipped while
    /// OwnerLivenessGate says no owner can have left since the last read.
    ///
    /// Returns the apps Thaw tracks an item for that the read found running a new process, for
    /// the caller to rescan. An agent app can relaunch without a launch notice, and a hidden one
    /// leaves the drawn bar as it was, so no other trigger reads its items.
    @discardableResult
    func purgeDepartedOwnersWhenDue(
        probe: OwnerLivenessProbe = .live,
        now: ContinuousClock.Instant = .now,
        readOwners: @Sendable () async -> RunningApplicationSnapshot = { await RunningApplicationSnapshot.current() }
    ) async -> Set<String> {
        let signature = probe.runningApplications()
        let ownersAlive = itemCache.livenessPIDs.allSatisfy(probe.isAlive)
        guard !ownerPurge.isRunning,
              ownerPurge.gate.isReadDue(ownersAlive: ownersAlive, signature: signature, now: now)
        else { return [] }
        let owners = await purgeDepartedOwners(readOwners: readOwners)
        ownerPurge.gate.noteRead(signature: signature, at: now)
        guard let owners else { return [] }
        return ownerPurge.noteRunning(owners.bundleIdentifiersByPID).filter {
            Self.tracksMenuBarItem(bundleID: $0, in: knownItemIdentifiers)
        }
    }
}
