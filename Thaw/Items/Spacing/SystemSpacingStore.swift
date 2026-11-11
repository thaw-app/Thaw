//
//  SystemSpacingStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Where Thaw reads and writes the menu bar spacing macOS draws items with:
/// NSStatusItemSpacing and NSStatusItemSelectionPadding in the current host's global domain.
///
/// Only tests replace current, with a scratch store (see ScratchDefaultsTrait). The real values
/// are the user's menu bar spacing, and a test that sets up the display settings writes them.
/// The unchecked annotation covers only that test-setup reassignment, as for Defaults.store.
nonisolated struct SystemSpacingStore: Sendable {
    /// The value for the key, or nil when it is unset.
    let read: @Sendable (_ key: String) -> Int?
    /// Writes the value for the key.
    let write: @Sendable (_ key: String, _ value: Int) async throws -> Void

    /// The store a new MenuBarItemSpacingManager keeps, and DisplaySettingsManager reads.
    static nonisolated(unsafe) var current: SystemSpacingStore = .live
}
