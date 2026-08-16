//
//  TestBootstrap.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import Thaw

/// Instantiated once by the test runner (`NSPrincipalClass`) before any
/// test in the bundle executes.
///
/// Points the process-wide `Defaults` facade at a scratch suite so no
/// suite can write to the real `com.stonerl.Thaw` domain of whoever is
/// running the tests. Suites using `withScratchDefaults` compose with
/// this unchanged: they swap in their own per-test suite and restore the
/// previous store, which is now this scratch base rather than
/// `.standard`. Suites that call `Defaults.set` directly no longer need
/// per-key snapshot/restore to be safe, though existing ones stay
/// correct.
///
/// The app host has already launched and read its state from the real
/// domain by the time the test bundle loads; only reads and writes made
/// from test code are redirected.
@objc(TestBootstrap)
final class TestBootstrap: NSObject {
    override init() {
        super.init()
        let suiteName = "com.stonerl.ThawTests.processScratch"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return
        }
        // Fresh domain every run; residue from a previous crashed or
        // interrupted run must not leak into this one.
        suite.removePersistentDomain(forName: suiteName)
        Defaults.store = suite
    }
}
