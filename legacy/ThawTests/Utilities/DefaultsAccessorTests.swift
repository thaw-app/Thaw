//
//  DefaultsAccessorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The typed `Defaults` accessors with no caller elsewhere in the app.
///
/// Serialized because `Defaults.store` is process-wide. The accessors ignore
/// the key's meaning, so each test picks any key of the matching type.
@Suite("Defaults accessors", .serialized)
struct DefaultsAccessorTests {
    /// `globalDomain` reads `NSGlobalDomain`, not the app's domain, so a value
    /// written through the facade must not show up in it.
    @Test("globalDomain reads the shared domain rather than the app's own")
    func globalDomainDoesNotSeeTheAppDomain() throws {
        try withScratchDefaults { _ in
            Defaults.set("thaw-defaults-accessor", forKey: .newItemsSection)

            #expect(Defaults.string(forKey: .newItemsSection) == "thaw-defaults-accessor")
            #expect(Defaults.globalDomain[Defaults.Key.newItemsSection.rawValue] == nil)
        }
    }
}
