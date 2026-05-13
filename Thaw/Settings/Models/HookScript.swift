//
//  HookScript.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A single user-supplied script run as a profile-apply hook.
///
/// The path is stored verbatim. Whether the file is invoked directly or
/// routed through osascript is decided at run time by the extension, so
/// the user can replace the file behind the scenes without re-picking it.
struct HookScript: Codable, Hashable {
    /// Absolute path to the script file on disk.
    var path: String

    /// Maximum wall-clock seconds the hook may run before Thaw terminates it.
    /// Clamped to [1, 300] at run time; storing the raw value keeps the
    /// Stepper binding straightforward.
    var timeoutSeconds: Double

    /// When false, the hook is skipped without removing the path. Lets
    /// users park a configured script without losing the path.
    var isEnabled: Bool

    init(path: String, timeoutSeconds: Double = 5, isEnabled: Bool = true) {
        self.path = path
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
    }
}

// MARK: - ProfileAutomation

/// Per-profile hook configuration. Optional inside Profile for forward
/// compatibility: profiles on disk written before this field existed
/// decode with automation = nil.
struct ProfileAutomation: Codable, Hashable {
    var preHook: HookScript?
    var postHook: HookScript?

    init(preHook: HookScript? = nil, postHook: HookScript? = nil) {
        self.preHook = preHook
        self.postHook = postHook
    }

    /// True when neither hook is set. Used by the manager to elide writing
    /// an empty container into the profile JSON.
    var isEmpty: Bool { preHook == nil && postHook == nil }
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
    /// Loads the global hook for the given phase from UserDefaults, or
    /// returns nil if none configured / decode fails.
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
