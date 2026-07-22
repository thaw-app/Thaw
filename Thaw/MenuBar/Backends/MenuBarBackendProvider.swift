//
//  MenuBarBackendProvider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarHost
import MenuBarModel
import PlatformRuntimeKit

/// Selects the menu-bar policy backend for the host OS.
///
/// Lives in the app so `PlatformRuntimeKit` does not depend on `MenuBarHost`.
/// Runtime builds use `RuntimeMenuBarBackend`; host-native builds use
/// `HostMenuBarBackend`.
nonisolated enum MenuBarBackendProvider {
    static let current: any MenuBarBackend = {
        if #available(macOS 27, *) {
            return RuntimeMenuBarBackend()
        } else {
            return HostMenuBarBackend()
        }
    }()

    /// Selects the backend implied by a `usesVisibilityRestrictions` flag,
    /// independent of the host OS. Callers that only carry the boolean (the
    /// image cache's capture-section resolver and its tests) route through the
    /// same adapters as ``current`` instead of hand-constructing one.
    static nonisolated func backend(usesVisibilityRestrictions: Bool) -> any MenuBarBackend {
        usesVisibilityRestrictions ? RuntimeMenuBarBackend() : HostMenuBarBackend()
    }
}
