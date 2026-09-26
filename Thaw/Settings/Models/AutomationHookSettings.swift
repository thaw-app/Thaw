//
//  AutomationHookSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Observation

/// Manages the two global profile hooks shown in AutomationSettingsPane.
///
/// Per-profile hooks live in each profile's JSON and go through ProfileManager.
@MainActor
@Observable
final class AutomationHookSettings {
    var globalPreHook: HookScript? {
        didSet {
            guard !suppressPersist else { return }
            HookScript.saveGlobal(globalPreHook, phase: .pre)
        }
    }

    var globalPostHook: HookScript? {
        didSet {
            guard !suppressPersist else { return }
            HookScript.saveGlobal(globalPostHook, phase: .post)
        }
    }

    /// Suppresses the didSet writeback while loading from defaults.
    @ObservationIgnored
    private var suppressPersist = false

    init() {
        suppressPersist = true
        globalPreHook = HookScript.loadGlobal(.pre)
        globalPostHook = HookScript.loadGlobal(.post)
        suppressPersist = false
    }
}
