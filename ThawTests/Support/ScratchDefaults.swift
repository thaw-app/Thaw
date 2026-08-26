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
/// - Note: this protects suites that go through the synchronous
///   `withScratchDefaults`; the async variant serializes through
///   ``ScratchDefaultsMutex`` instead. A suite that reads the real `Defaults`
///   domain without taking the lock can still observe someone else's scratch
///   store. The end state is for every `Defaults`-touching suite to route
///   through here.
private let scratchDefaultsLock = OSAllocatedUnfairLock()

/// Serializes the async variant's store swap across the whole process.
///
/// The unfair lock above cannot be held across a suspension point, so the
/// async variant suspends on this actor-backed mutex instead and holds it for
/// the whole body, suspensions included. Waiters resume in FIFO order, and
/// `release()` hands the mutex to the next waiter without ever letting a
/// third party sneak in between.
///
/// - Warning: like the unfair lock, this mutex is non-recursive: a nested
///   acquisition waits on itself forever. It is also independent of
///   `scratchDefaultsLock`, so a synchronous and an asynchronous caller do
///   not exclude each other.
private actor ScratchDefaultsMutex {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            // Hand the mutex to the next waiter without unlocking.
            waiters.removeFirst().resume()
        }
    }
}

private let scratchDefaultsMutex = ScratchDefaultsMutex()

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
///
/// - Warning: `scratchDefaultsLock` is non-recursive. A nested
///   `withScratchDefaults` call on the same thread — that is, from inside
///   `body` — is unsupported and will deadlock.
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
/// Saving, installing, and restoring `Defaults.store` are serialized through
/// ``ScratchDefaultsMutex``: an unfair lock cannot be held across a
/// suspension point, so this variant suspends on the actor-backed mutex
/// instead and holds it for the whole body, suspensions included. Prefer the
/// synchronous variant wherever the body does not actually need to await.
///
/// - Warning: the mutex is non-recursive: nesting a `withScratchDefaults`
///   call inside `body` deadlocks. It is also independent of the synchronous
///   variant's lock, so async and sync callers do not exclude each other.
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
    await scratchDefaultsMutex.acquire()
    let previous = Defaults.store
    Defaults.store = suite
    defer {
        // The restore and cleanup below run synchronously before the release
        // task is spawned, so the next acquirer can only ever see the
        // restored store.
        Defaults.store = previous
        suite.removePersistentDomain(forName: suiteName)
        Task { await scratchDefaultsMutex.release() }
    }
    return try await body(suite)
}

