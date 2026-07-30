//
//  AutomationHookSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// Manages the two global profile hooks shown in AutomationSettingsPane.
///
/// Per-profile hooks live inside each Profile JSON; the pane reads and
/// writes them directly through ProfileManager and does not need to be
/// mirrored here.
@MainActor
final class AutomationHookSettings: ObservableObject {
    @Published var globalPreHook: HookScript? {
        didSet {
            guard !suppressPersist else { return }
            HookScript.saveGlobal(globalPreHook, phase: .pre)
        }
    }

    @Published var globalPostHook: HookScript? {
        didSet {
            guard !suppressPersist else { return }
            HookScript.saveGlobal(globalPostHook, phase: .post)
        }
    }

    /// True while loading from defaults; suppresses writeback in the
    /// @Published didSet so we do not echo the initial load back to disk.
    private var suppressPersist = false

    init() {
        suppressPersist = true
        globalPreHook = HookScript.loadGlobal(.pre)
        globalPostHook = HookScript.loadGlobal(.post)
        suppressPersist = false
    }
}
