//
//  DefaultsIsolationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Guards the process-wide defaults isolation `TestBootstrap` installs.
///
/// The bootstrap is wired through `NSPrincipalClass` in the generated
/// Info.plist, so a renamed class or dropped build setting would silently
/// send every unscoped `Defaults.set` to the real `com.stonerl.Thaw` domain.
///
/// `withScratchDefaults` in a parallel test swaps in another scratch suite,
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
