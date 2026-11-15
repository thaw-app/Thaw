//
//  MenuBarItemManager+OwnerLiveness.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// What the periodic liveness check remembers between ticks.
struct OwnerPurgeState {
    /// Whether a read of the process table is in flight.
    var isRunning = false
    var gate = OwnerLivenessGate<Set<ObjectIdentifier>>()
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

    /// The tick's liveness check: purgeDepartedOwners(readOwners:), skipped while
    /// OwnerLivenessGate says no owner can have left since the last read.
    func purgeDepartedOwnersWhenDue(
        probe: OwnerLivenessProbe = .live,
        now: ContinuousClock.Instant = .now,
        readOwners: @Sendable () async -> RunningApplicationSnapshot = { await RunningApplicationSnapshot.current() }
    ) async {
        let signature = probe.runningApplications()
        let ownersAlive = itemCache.livenessPIDs.allSatisfy(probe.isAlive)
        guard !ownerPurge.isRunning,
              ownerPurge.gate.isReadDue(ownersAlive: ownersAlive, signature: signature, now: now)
        else { return }
        await purgeDepartedOwners(readOwners: readOwners)
        ownerPurge.gate.noteRead(signature: signature, at: now)
    }
}
