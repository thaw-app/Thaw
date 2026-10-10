//
//  MenuBarBackendProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit

/// Supplies the menu-bar policy backend.
///
/// macOS 27 retired the WindowServer model the legacy host backend was built
/// on, so RuntimeMenuBarBackend is the only backend. The type is kept as a
/// seam because callers reference it widely and because it still isolates the
/// app from PlatformRuntimeKit's concrete type.
nonisolated enum MenuBarBackendProvider {
    static let current: any MenuBarBackend = RuntimeMenuBarBackend()

    /// Returns the backend for a usesVisibilityRestrictions flag.
    ///
    /// The flag no longer selects between backends, assertion-backed
    /// visibility is the only implementation, but the entry point is retained
    /// for the image cache's capture-section resolver and its tests, which
    /// carry the boolean rather than a backend.
    static nonisolated func backend(usesVisibilityRestrictions _: Bool) -> any MenuBarBackend {
        RuntimeMenuBarBackend()
    }
}
