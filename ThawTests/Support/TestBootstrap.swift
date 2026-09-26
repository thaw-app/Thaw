//
//  TestBootstrap.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import Thaw

/// Instantiated once by the test runner (`NSPrincipalClass`) before any
/// test in the bundle executes.
///
/// Points the process-wide `Defaults` facade at a scratch suite so no
/// suite can write to the real `com.stonerl.Thaw` domain. Suites using
/// `withScratchDefaults` restore to this scratch base rather than
/// `.standard`.
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
