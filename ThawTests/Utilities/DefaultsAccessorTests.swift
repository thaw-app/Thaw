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
    @Test("array(forKey:) returns the stored array")
    func arrayForKeyReturnsTheStoredArray() throws {
        try withScratchDefaults { suite in
            suite.set(["visible", "hidden", "alwaysHidden"], forKey: Defaults.Key.searchSectionOrder.rawValue)

            let stored = try #require(Defaults.array(forKey: .searchSectionOrder) as? [String])

            #expect(stored == ["visible", "hidden", "alwaysHidden"])
        }
    }

    @Test("array(forKey:) is nil for an unset key")
    func arrayForKeyIsNilWhenUnset() throws {
        try withScratchDefaults { _ in
            #expect(Defaults.array(forKey: .searchSectionOrder) == nil)
        }
    }

    /// A non-array value must read as `nil` rather than trap; a settings URI or a
    /// hand-edited plist can put anything there.
    @Test("array(forKey:) is nil when the stored value is not an array")
    func arrayForKeyIsNilForAMismatchedType() throws {
        try withScratchDefaults { suite in
            suite.set("not an array", forKey: Defaults.Key.searchSectionOrder.rawValue)

            #expect(Defaults.array(forKey: .searchSectionOrder) == nil)
        }
    }

    @Test("float(forKey:) returns the stored value")
    func floatForKeyReturnsTheStoredValue() throws {
        try withScratchDefaults { suite in
            // 0.75 is exactly representable, so this is not a tolerance test.
            suite.set(0.75, forKey: Defaults.Key.showOnHoverDelay.rawValue)

            #expect(Defaults.float(forKey: .showOnHoverDelay) == 0.75)
        }
    }

    /// `UserDefaults.float(forKey:)` has no optional form, so an unset key reads as zero.
    @Test("float(forKey:) is zero for an unset key")
    func floatForKeyIsZeroWhenUnset() throws {
        try withScratchDefaults { _ in
            #expect(Defaults.float(forKey: .showOnHoverDelay) == 0)
        }
    }

    @Test("url(forKey:) resolves a stored path")
    func urlForKeyResolvesAStoredPath() throws {
        try withScratchDefaults { suite in
            suite.set("/nonexistent/thaw-defaults-accessor/file.txt", forKey: Defaults.Key.menuBarSearchPanelFrame.rawValue)

            let url = try #require(Defaults.url(forKey: .menuBarSearchPanelFrame))

            #expect(url.path == "/nonexistent/thaw-defaults-accessor/file.txt")
            #expect(url.lastPathComponent == "file.txt")
        }
    }

    @Test("url(forKey:) is nil for an unset key")
    func urlForKeyIsNilWhenUnset() throws {
        try withScratchDefaults { _ in
            #expect(Defaults.url(forKey: .menuBarSearchPanelFrame) == nil)
        }
    }

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
