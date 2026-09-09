//
//  SpacingRelaunchPolicy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How the spacing relaunch wave is allowed to restart one running
/// application.
nonisolated enum SpacingRelaunchStrategy: Equatable {
    /// Hand the restart to launchd via launchctl kickstart -k. The only
    /// route that works for a launch-constrained agent, because launchd
    /// stays the launching parent.
    case launchdKickstart(label: String)

    /// Quit the app and launch the same bundle back.
    case terminateAndLaunch(bundleURL: URL)

    /// Leave the process alone. Its status item keeps the previous spacing
    /// until the app next starts on its own.
    case leaveRunning(reason: SpacingRelaunchSkipReason)
}

/// Why an app is excluded from the relaunch wave.
nonisolated enum SpacingRelaunchSkipReason: String, Equatable {
    /// The executable ships with macOS and no LaunchAgent claims it. AMFI
    /// launch constraints reject a spawn whose parent is not the one the
    /// binary was built to accept, so terminating it is one-way. (#1070)
    case systemOwnedExecutable

    /// No bundle to launch back: XPC helpers, plug-in hosts, and app
    /// extensions have no Launch Services target.
    case noRelaunchableBundle
}

/// Decides how the spacing relaunch wave may treat each app that owns a
/// menu bar item.
///
/// Rewriting NSStatusItemSpacing only reaches a status item when its
/// owning process restarts, so the wave is what makes a spacing change
/// visible right away. What it must not do is terminate a process it cannot
/// bring back.
///
/// Spotlight and TextInputMenuAgent are the case that motivated this:
/// terminating them is a successful exit, so an agent with
/// KeepAlive.SuccessfulExit = false is never respawned by launchd, and
/// relaunching the bundle ourselves is SIGKILLed at exec (CODESIGNING,
/// "Launch Constraint Violation"). The item stays gone until reboot, and
/// Cmd + Space stops working with it. Both are indexed LaunchAgents and
/// come back through kickstart, but the same constraint covers system
/// binaries that no agent in SystemLaunchAgentIndex claims — those are
/// skipped rather than gambled on. (#1070, #720)
nonisolated enum SpacingRelaunchPolicy {
    /// Path prefixes owned by macOS. Everything below them is either a
    /// platform binary or installed by the OS, and neither is ours to
    /// terminate without a launchd label to restore it with.
    ///
    /// /System covers the sealed system volume, including the
    /// CoreServices agents that carry launch constraints.
    static let systemPathPrefixes = [
        "/System/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/Library/Apple/",
    ]

    /// The strategy for an app described by the values captured from its
    /// running process.
    ///
    /// launchdLabel wins over everything: a kickstart restarts the job in
    /// place, which is both the safe route for a constrained binary and the
    /// only one that respects the agent's KeepAlive policy.
    static func strategy(
        executableURL: URL?,
        bundleURL: URL?,
        bundleIdentifier: String?,
        launchdLabel: String?
    ) -> SpacingRelaunchStrategy {
        if let launchdLabel, !launchdLabel.isEmpty {
            return .launchdKickstart(label: launchdLabel)
        }
        // Classify on both paths: a helper can live inside a system bundle
        // while reporting a different bundle URL, and either spelling is
        // enough to make the spawn constrained.
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

    /// Whether the given location sits under a macOS-owned path prefix.
    ///
    /// A missing URL counts as not system-owned on its own; the caller
    /// passes both the executable and the bundle, and the remaining
    /// guard rejects an app that has neither.
    static func isSystemOwned(_ url: URL?) -> Bool {
        guard let url else {
            return false
        }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return systemPathPrefixes.contains { path.hasPrefix($0) }
    }
}
