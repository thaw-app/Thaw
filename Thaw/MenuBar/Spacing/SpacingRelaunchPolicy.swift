//
//  SpacingRelaunchPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How the spacing relaunch wave may restart one running application.
nonisolated enum SpacingRelaunchStrategy: Equatable {
    /// `launchctl kickstart -k`. The only route for a launch-constrained
    /// agent, because launchd stays the launching parent.
    case launchdKickstart(label: String)

    /// Quit the app and launch the same bundle back.
    case terminateAndLaunch(bundleURL: URL)

    /// Leave the process alone. Its status item keeps the previous spacing
    /// until the app next starts on its own.
    case leaveRunning(reason: SpacingRelaunchSkipReason)
}

/// Why an app is excluded from the relaunch wave.
nonisolated enum SpacingRelaunchSkipReason: String, Equatable {
    /// Ships with macOS and no LaunchAgent claims it. AMFI launch constraints
    /// reject any other parent, so terminating it is one-way.
    case systemOwnedExecutable

    /// No bundle to launch back: XPC helpers, plug-in hosts, and app
    /// extensions have no Launch Services target.
    case noRelaunchableBundle
}

/// Decides how the spacing relaunch wave treats each app that owns a menu
/// bar item. It must never terminate a process it cannot bring back.
///
/// Terminating an agent with `KeepAlive.SuccessfulExit = false` (Spotlight,
/// TextInputMenuAgent) means launchd never respawns it, and relaunching the
/// bundle ourselves is SIGKILLed at exec ("Launch Constraint Violation").
/// Unindexed system binaries are skipped for the same reason.
nonisolated enum SpacingRelaunchPolicy {
    /// Path prefixes owned by macOS. Nothing below them is ours to terminate
    /// without a launchd label to restore it with.
    static let systemPathPrefixes = [
        "/System/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/Library/Apple/",
    ]

    /// `launchdLabel` wins over everything: kickstart is safe for constrained
    /// binaries and respects the agent's KeepAlive policy.
    static func strategy(
        executableURL: URL?,
        bundleURL: URL?,
        bundleIdentifier: String?,
        launchdLabel: String?
    ) -> SpacingRelaunchStrategy {
        if let launchdLabel, !launchdLabel.isEmpty {
            return .launchdKickstart(label: launchdLabel)
        }
        // A helper can live in a system bundle while reporting a different
        // bundle URL, so check both.
        if isSystemOwned(executableURL) || isSystemOwned(bundleURL) {
            return .leaveRunning(reason: .systemOwnedExecutable)
        }
        guard
            let bundleURL,
            let bundleIdentifier,
            !bundleIdentifier.isEmpty
        else {
            return .leaveRunning(reason: .noRelaunchableBundle)
        }
        return .terminateAndLaunch(bundleURL: bundleURL)
    }

    /// A missing URL counts as not system-owned; the caller checks both URLs.
    static func isSystemOwned(_ url: URL?) -> Bool {
        guard let url else {
            return false
        }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return systemPathPrefixes.contains { path.hasPrefix($0) }
    }
}
