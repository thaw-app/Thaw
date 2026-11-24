//
//  TestHostingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Test hosting", .scratchDefaults)
struct TestHostingTests {
    @Test("Isolating preferences swaps in an empty private suite")
    func isolatesPreferences() throws {
        let stale = try #require(UserDefaults(suiteName: TestHosting.preferencesSuiteName))
        stale.set("stale", forKey: "leftover")
        defer { stale.removePersistentDomain(forName: TestHosting.preferencesSuiteName) }

        TestHosting.isolatePreferences()

        Defaults.store.set("written", forKey: "probe")
        let suite = try #require(UserDefaults(suiteName: TestHosting.preferencesSuiteName))
        #expect(suite.string(forKey: "probe") == "written")
        #expect(Defaults.store.object(forKey: "leftover") == nil)
    }
}
