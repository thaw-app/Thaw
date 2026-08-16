//
//  DefaultsIsolationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Guards the process-wide defaults isolation `TestBootstrap` installs.
///
/// The bootstrap is wired through `NSPrincipalClass` in the test bundle's
/// generated Info.plist, so nothing in the type system keeps it alive: a
/// renamed class or a dropped build setting reverts every unscoped
/// `Defaults.set` in the suite to writing the real `com.stonerl.Thaw`
/// domain of whoever runs the tests — silently. These expectations fail
/// loudly instead.
///
/// Both hold even while another parallel test is inside
/// `withScratchDefaults`: that helper swaps in a different scratch suite,
/// which is still not `.standard`.
@Suite("Defaults isolation")
struct DefaultsIsolationTests {
    @Test("The Defaults facade does not point at the standard store")
    func facadeDoesNotUseStandardStore() {
        #expect(Defaults.store !== UserDefaults.standard)
    }

    @Test("A write through the facade never lands in the standard store")
    func writesDoNotReachStandardStore() {
        // Captured once: a parallel test inside withScratchDefaults can swap
        // the process-wide store between the write and the cleanup.
        let store = Defaults.store
        let key = "DefaultsIsolationTests.sentinel.\(UUID().uuidString)"
        store.set(true, forKey: key)
        defer {
            store.removeObject(forKey: key)
        }

        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }
}
