//
//  SingleInstanceRule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Decides whether this launch of Thaw may go on while other copies of Thaw are running.
/// Every input is a value, so the rule is tested without launching anything.
nonisolated enum SingleInstanceRule {
    /// Thaw passes its own process identifier to the copy it starts when it restarts itself.
    static let relaunchArgument = "--relaunched-from"

    /// The release bundle identifier. Other builds append one component, such as `.debug`.
    static let baseBundleIdentifier = "com.stonerl.Thaw"

    /// Bundles under Thaw's identifier that are parts of Thaw, not copies of the app.
    private static let componentSuffixes: Set = ["MenuBarCaptureService", "ThawControls", "tests"]

    /// How this process was started.
    enum LaunchMode: Equatable {
        case app
        case settingsProcess
        case visibilityRecovery
        case testHost
    }

    /// One running process, reduced to what the rule reads.
    struct RunningProcess: Equatable {
        var processIdentifier: pid_t
        var parentProcessIdentifier: pid_t?
        var bundleIdentifier: String?
        var localizedName: String?
        var isTerminated = false

        /// The name shown to people, or the bundle identifier when the app has none.
        var displayName: String {
            localizedName ?? bundleIdentifier ?? String(processIdentifier)
        }
    }

    /// What this launch learned from the instance lock, which every normal app launch takes.
    enum LockState: Equatable {
        case acquired
        case heldElsewhere
        /// The lock file couldn't be opened, so only the running apps tell whether another copy runs.
        case unavailable
    }

    enum Decision: Equatable {
        case proceed
        /// Another copy runs. `others` lists the copies found among the running apps, which can be empty
        /// when only the lock shows one.
        case ask(others: [RunningProcess], lockHeldElsewhere: Bool)
    }

    /// How the prompt names the other copies.
    enum Wording: Equatable {
        case unnamed
        case one(String)
        case several([String])

        init(_ others: [RunningProcess]) {
            var seen = Set<String>()
            let names = others.map(\.displayName).filter { seen.insert($0).inserted }
            switch names.count {
            case 0: self = .unnamed
            case 1: self = .one(names[0])
            default: self = .several(names)
            }
        }
    }

    /// True for the main app of any Thaw build, or for this build's own bundle when it was renamed.
    static func isThawApp(bundleIdentifier: String?, ownBundleIdentifier: String? = nil) -> Bool {
        guard let bundleIdentifier else { return false }
        if bundleIdentifier == baseBundleIdentifier || bundleIdentifier == ownBundleIdentifier {
            return true
        }
        guard bundleIdentifier.hasPrefix(baseBundleIdentifier + ".") else { return false }
        let suffix = bundleIdentifier.dropFirst(baseBundleIdentifier.count + 1)
        return !suffix.isEmpty && !suffix.contains(".") && !componentSuffixes.contains(String(suffix))
    }

    static func launchMode(arguments: [String], environment: [String: String]) -> LaunchMode {
        if TestHosting.isActive(environment: environment) {
            return .testHost
        }
        if arguments.contains(SettingsProcessRoute.launchArgument) {
            return .settingsProcess
        }
        if arguments.contains(NativeVisibilityRecoveryLaunch.argument) {
            return .visibilityRecovery
        }
        return .app
    }

    /// The launch arguments that tell the new copy which process it replaces.
    static func relaunchArguments(replacing processIdentifier: pid_t) -> [String] {
        [relaunchArgument, String(processIdentifier)]
    }

    /// The process this copy replaces, when it was started by a restart.
    static func relaunchedFrom(arguments: [String]) -> pid_t? {
        guard let index = arguments.firstIndex(of: relaunchArgument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return pid_t(arguments[index + 1])
    }

    /// Only a normal app launch checks. A lock held by another process always means another copy runs.
    /// The copy this one replaces on a restart and children of this process, of that copy or of another
    /// copy, such as their Settings processes, are left out of the list of copies.
    static func decide(
        ownProcessIdentifier: pid_t,
        ownBundleIdentifier: String?,
        launchMode: LaunchMode,
        lock: LockState,
        relaunchedFrom: pid_t?,
        running: [RunningProcess]
    ) -> Decision {
        guard launchMode == .app else { return .proceed }
        let copies = running.filter { process in
            process.processIdentifier != ownProcessIdentifier && process.processIdentifier != relaunchedFrom
                && !process.isTerminated
                && isThawApp(bundleIdentifier: process.bundleIdentifier, ownBundleIdentifier: ownBundleIdentifier)
        }
        let parents = Set([ownProcessIdentifier, relaunchedFrom].compactMap(\.self) + copies.map(\.processIdentifier))
        let others = copies.filter { process in
            process.parentProcessIdentifier.map { !parents.contains($0) } ?? true
        }
        let heldElsewhere = lock == .heldElsewhere
        guard heldElsewhere || !others.isEmpty else { return .proceed }
        return .ask(others: others, lockHeldElsewhere: heldElsewhere)
    }
}
