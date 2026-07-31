//
//  CoverageSweep3Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Coverage sweep, part 3: the `Defaults` facade accessors that no other
/// suite reaches.
///
/// `DefaultsKeyTests` pins the hidden diagnostic keys and their defaults;
/// everything else in `Defaults.swift` is only ever exercised indirectly by
/// whichever settings model happens to use it. `array(forKey:)`,
/// `float(forKey:)` and `url(forKey:)` currently have no such caller, and
/// `globalDomain` reads a *different* domain from every other accessor —
/// which is the one thing about it worth pinning, because a facade that
/// quietly read the app domain instead would still return a plausible
/// dictionary.
///
/// Every test routes through ``withScratchDefaults(sourceLocation:_:)``, so
/// nothing here touches the developer's real `com.stonerl.Thaw` domain. The
/// suite is `.serialized` for the reason that helper documents:
/// `Defaults.store` is process-wide.
///
/// Deliberate gap: the accessors are key-agnostic pass-throughs, so each
/// test picks a key whose stored type matches the accessor rather than
/// asserting anything about that particular setting.
@Suite("Coverage sweep 3: Defaults facade accessors", .serialized)
struct CoverageSweep3Tests {
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

    /// A key holding something that is not an array must read as `nil`
    /// rather than trapping — the value can be anything a settings URI or a
    /// hand-edited plist put there.
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

    /// `UserDefaults.float(forKey:)` has no optional form: an unset key
    /// reads as zero, which is why every caller has to supply its own
    /// default separately.
    @Test("float(forKey:) is zero for an unset key")
    func floatForKeyIsZeroWhenUnset() throws {
        try withScratchDefaults { _ in
            #expect(Defaults.float(forKey: .showOnHoverDelay) == 0)
        }
    }

    @Test("url(forKey:) resolves a stored path")
    func urlForKeyResolvesAStoredPath() throws {
        try withScratchDefaults { suite in
            suite.set("/nonexistent/thaw-coverage-sweep/file.txt", forKey: Defaults.Key.menuBarSearchPanelFrame.rawValue)

            let url = try #require(Defaults.url(forKey: .menuBarSearchPanelFrame))

            #expect(url.path == "/nonexistent/thaw-coverage-sweep/file.txt")
            #expect(url.lastPathComponent == "file.txt")
        }
    }

    @Test("url(forKey:) is nil for an unset key")
    func urlForKeyIsNilWhenUnset() throws {
        try withScratchDefaults { _ in
            #expect(Defaults.url(forKey: .menuBarSearchPanelFrame) == nil)
        }
    }

    /// The point of `globalDomain` is that it reads `NSGlobalDomain` — the
    /// defaults every app sees — and not the app's own domain. A value
    /// written through the facade must therefore *not* show up in it.
    @Test("globalDomain reads the shared domain rather than the app's own")
    func globalDomainDoesNotSeeTheAppDomain() throws {
        try withScratchDefaults { _ in
            Defaults.set("thaw-coverage-sweep", forKey: .newItemsSection)

            #expect(Defaults.string(forKey: .newItemsSection) == "thaw-coverage-sweep")
            #expect(Defaults.globalDomain[Defaults.Key.newItemsSection.rawValue] == nil)
        }
    }
}
