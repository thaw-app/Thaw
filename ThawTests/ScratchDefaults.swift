//
//  ScratchDefaults.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Points ``Defaults`` at a throwaway suite for the duration of `body`, then
/// restores the previous store and deletes the suite.
///
/// Anything that persists a setting -- `ProfileManager.applySnapshot`,
/// `MenuBarItem.customName`, `MigrationManager`, `HookScript.saveGlobal` --
/// writes through the `Defaults` facade. Without a scratch store those writes
/// land in the real `com.stonerl.Thaw` domain and mutate the defaults of
/// whoever runs the suite.
///
/// This replaces the per-key snapshot/restore that `GeneralSettingsTests` and
/// `AdvancedSettingsTests` had to do by hand. Those worked, but they could
/// only protect keys they knew about, and their own doc comments flag that the
/// approach is unsound once suites run concurrently.
///
/// - Important: `Defaults.store` is process-wide. A suite calling this **must**
///   be `.serialized`, otherwise a sibling test running in parallel will read
///   through this suite's scratch store. Serialization scopes execution within
///   a suite, so a `.serialized` suite is safe even though the store is global.
@discardableResult
func withScratchDefaults<Result>(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: (UserDefaults) throws -> Result
) throws -> Result {
    let suiteName = "com.stonerl.ThawTests.\(UUID().uuidString)"
    let suite = try #require(
        UserDefaults(suiteName: suiteName),
        "could not open a scratch defaults suite",
        sourceLocation: sourceLocation
    )
    let previous = Defaults.store
    Defaults.store = suite
    defer {
        Defaults.store = previous
        suite.removePersistentDomain(forName: suiteName)
    }
    return try body(suite)
}

/// Async counterpart to ``withScratchDefaults(sourceLocation:_:)``.
///
/// The same `.serialized` requirement applies, and more sharply: an `await`
/// inside `body` suspends while the global store still points at the scratch
/// suite.
@discardableResult
func withScratchDefaults<Result>(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: (UserDefaults) async throws -> Result
) async throws -> Result {
    let suiteName = "com.stonerl.ThawTests.\(UUID().uuidString)"
    let suite = try #require(
        UserDefaults(suiteName: suiteName),
        "could not open a scratch defaults suite",
        sourceLocation: sourceLocation
    )
    let previous = Defaults.store
    Defaults.store = suite
    defer {
        Defaults.store = previous
        suite.removePersistentDomain(forName: suiteName)
    }
    return try await body(suite)
}
