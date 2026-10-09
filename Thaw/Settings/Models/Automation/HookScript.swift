//
//  HookScript.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Store the path verbatim and choose direct execution or osascript by extension at runtime.
/// Users can replace the file without picking it again.
struct HookScript: Codable, Hashable {
    /// Absolute path to the script file on disk.
    var path: String

    /// Wall-clock timeout clamped to [1, 300] at runtime; store the raw value for the Stepper binding.
    var timeoutSeconds: Double

    /// Disable without removing the configured path.
    var isEnabled: Bool

    init(path: String, timeoutSeconds: Double = 5, isEnabled: Bool = true) {
        self.path = path
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
    }
}

// MARK: - ProfileAutomation

/// Optional in Profile so records without this field decode with automation = nil.
struct ProfileAutomation: Codable, Hashable {
    var preHook: HookScript?
    var postHook: HookScript?

    init(preHook: HookScript? = nil, postHook: HookScript? = nil) {
        self.preHook = preHook
        self.postHook = postHook
    }

    /// Lets the manager omit empty automation from profile JSON.
    var isEmpty: Bool {
        preHook == nil && postHook == nil
    }

    /// The same hooks, switched off. For a profile that came from a file: its hooks name scripts
    /// someone else chose, and applying the profile would run them. They stay listed, so the user
    /// can read the path and switch each one on.
    var disabledUntilApproved: ProfileAutomation {
        func off(_ hook: HookScript?) -> HookScript? {
            guard var hook else { return nil }
            hook.isEnabled = false
            return hook
        }
        return ProfileAutomation(preHook: off(preHook), postHook: off(postHook))
    }
}

// MARK: - HookPhase / HookScope

enum HookPhase: String {
    case pre
    case post
}

enum HookScope: String {
    case global
    case profile
}

// MARK: - Global hook persistence

extension HookScript {
    /// Returns nil for absent or undecodable global hooks.
    static func loadGlobal(_ phase: HookPhase) -> HookScript? {
        let key: Defaults.Key = (phase == .pre) ? .globalPreProfileHook : .globalPostProfileHook
        guard let data = Defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HookScript.self, from: data)
    }

    /// Persists the global hook for the given phase, or clears it when nil.
    static func saveGlobal(_ hook: HookScript?, phase: HookPhase) {
        let key: Defaults.Key = (phase == .pre) ? .globalPreProfileHook : .globalPostProfileHook
        guard let hook else {
            Defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(hook) {
            Defaults.set(data, forKey: key)
        }
    }
}
