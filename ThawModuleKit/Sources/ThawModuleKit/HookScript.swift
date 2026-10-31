//
//  HookScript.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A script to run, by path. Whether it runs directly or through osascript is
/// decided from its extension when it runs, so the file can be replaced
/// without picking it again.
public struct HookScript: Codable, Hashable, Sendable {
    /// Absolute path to the script file on disk.
    public var path: String

    /// How long the script may run, in seconds, clamped to 1...300 when it runs.
    public var timeoutSeconds: Double

    /// Whether the script runs. Off keeps the path for later.
    public var isEnabled: Bool

    /// How long a new script may run, in seconds.
    public static let defaultTimeout: Double = 5

    /// The timeouts a script may have, in seconds.
    public static let timeoutRange: ClosedRange<Double> = 1 ... 300

    /// The extensions that run through osascript instead of directly.
    public static let appleScriptExtensions: Set<String> = ["scpt", "applescript", "scptd"]

    public init(path: String, timeoutSeconds: Double = defaultTimeout, isEnabled: Bool = true) {
        self.path = path
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
    }

    /// The timeout the script runs with, inside timeoutRange.
    public var clampedTimeout: Double {
        Self.clamp(timeoutSeconds)
    }

    /// Whether the script runs through osascript, which only needs to read
    /// it, rather than directly, which needs it to be executable.
    public var usesOSAScript: Bool {
        Self.appleScriptExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    public static func clamp(_ timeout: Double) -> Double {
        min(max(timeout, timeoutRange.lowerBound), timeoutRange.upperBound)
    }
}

/// The scripts saved with one profile. A profile without any decodes with
/// none, so older profile files still read.
public struct ProfileAutomation: Codable, Hashable, Sendable {
    public var preHook: HookScript?
    public var postHook: HookScript?

    public init(preHook: HookScript? = nil, postHook: HookScript? = nil) {
        self.preHook = preHook
        self.postHook = postHook
    }

    /// Whether the profile has no scripts, so its file can leave them out.
    public var isEmpty: Bool {
        preHook == nil && postHook == nil
    }

    /// The same hooks, switched off. For a profile that came from a file: its hooks name scripts
    /// someone else chose, and applying the profile would run them. They stay listed, so the user
    /// can read the path and switch each one on.
    public var disabledUntilApproved: ProfileAutomation {
        func off(_ hook: HookScript?) -> HookScript? {
            guard var hook else { return nil }
            hook.isEnabled = false
            return hook
        }
        return ProfileAutomation(preHook: off(preHook), postHook: off(postHook))
    }
}

/// Whether a script runs before or after the switch.
public enum HookPhase: String, Sendable {
    case pre
    case post
}

/// Whether a script runs for every switch or for one profile.
public enum HookScope: String, Sendable {
    case global
    case profile
}
