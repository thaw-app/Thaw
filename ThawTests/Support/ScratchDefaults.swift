//
//  ScratchDefaults.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock
import Testing
@testable import Thaw

/// Serializes installation of a scratch store across the whole process.
///
/// `Defaults.store` is a single global. `.serialized` orders tests *within* a
/// suite, not across suites, so without this two suites could install scratch
/// stores concurrently and each would read the other's. The lock makes the
/// swap window mutually exclusive.
///
/// - Note: this protects suites that go through `withScratchDefaults`. A suite
///   that reads the real `Defaults` domain without taking the lock can still
///   observe someone else's scratch store. The end state is for every
///   `Defaults`-touching suite to route through here.
private let scratchDefaultsLock = OSAllocatedUnfairLock()

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
    scratchDefaultsLock.lock()
    let previous = Defaults.store
    Defaults.store = suite
    defer {
        Defaults.store = previous
        suite.removePersistentDomain(forName: suiteName)
        scratchDefaultsLock.unlock()
    }
    return try body(suite)
}

/// Async counterpart to ``withScratchDefaults(sourceLocation:_:)``.
///
/// - Warning: this variant deliberately does **not** take
///   ``scratchDefaultsLock``. Holding an unfair lock across a suspension point
///   risks deadlock, since the continuation may resume on a different thread.
///   An async body therefore has no cross-suite protection: use it only from a
///   suite that owns the store for its whole duration, and prefer the
///   synchronous variant wherever the body does not actually need to await.
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
