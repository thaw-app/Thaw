//
//  AccessRefusalRestart.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawAXCore

/// Starts Thaw again, once, when other apps refuse its Accessibility reads though it has the permission.
///
/// This happens when the system's permission service fails during login. Thaw then sees only its
/// own items for as long as it runs, and a new process is the only thing that is asked about again.
@MainActor
enum AccessRefusalRestart {
    private static let diagLog = DiagLog(category: "AccessRefusalRestart")

    /// Where the facts come from. Tests pass their own.
    struct Probe {
        var refusers: () async -> Set<pid_t>
        /// How many running apps had menu bar items before.
        var formerHosts: () -> Int
        var processTrusted: () -> Bool
        var helperTrusted: () -> Bool
        var startedByRestart: () -> Bool

        static let live = Probe(
            refusers: {
                let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map(\.processIdentifier)
                return await MenuBarItemAXProvider.persistentAccessRefusers(running: Set(running))
            },
            formerHosts: {
                let hosts = UnseenMenuBarHosts.formerHosts()
                return NSWorkspace.shared.runningApplications.count { !$0.isTerminated && $0.bundleIdentifier.map(hosts.contains) == true }
            },
            processTrusted: { AXHelpers.isProcessTrusted() },
            helperTrusted: { MenuBarAXSubprocess.helperIsTrusted },
            startedByRestart: { SingleInstanceRule.relaunchedFrom(arguments: ProcessInfo.processInfo.arguments) != nil }
        )
    }

    /// Asks for the restart when it is due. Returns whether it did.
    @discardableResult
    static func restartIfRefused(probe: Probe = .live, restart: () -> Void) async -> Bool {
        // The cheap facts first: the read of each refusing app only matters when they hold.
        guard !probe.startedByRestart(), probe.processTrusted(), probe.helperTrusted() else { return false }
        let refusers = await probe.refusers()
        let facts = AccessRefusalRecovery.Facts(
            refusers: refusers.count,
            formerHosts: probe.formerHosts(),
            processTrusted: probe.processTrusted(),
            helperTrusted: probe.helperTrusted(),
            startedByRestart: probe.startedByRestart()
        )
        guard AccessRefusalRecovery.shouldRestart(facts) else { return false }
        diagLog.warning(
            "\(refusers.count) of \(facts.formerHosts) app(s) refuse this process's Accessibility reads though the permission is granted; restarting once so they are asked again"
        )
        restart()
        return true
    }
}
