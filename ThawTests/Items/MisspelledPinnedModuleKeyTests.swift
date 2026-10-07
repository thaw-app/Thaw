//
//  MisspelledPinnedModuleKeyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Store hygiene removes pinned-module keys the agent never reads")
struct MisspelledPinnedModuleKeyTests {
    private let stale = "status:com.apple.MenuBarAgent::com.apple.menuextra.controlcenter-BentoBox-1"

    @Test("The accessibility-title spelling is misspelled, under any prefix")
    func titleSpellingIsMisspelled() {
        #expect(PositionStoreHygiene.isMisspelledPinnedModuleKey(stale))
        #expect(PositionStoreHygiene.isMisspelledPinnedModuleKey("module:com.apple.menuextra.controlcenter-BentoBox-12"))
    }

    @Test("The agent's own spelling and unrelated keys are kept")
    func otherKeysAreKept() {
        #expect(!PositionStoreHygiene.isMisspelledPinnedModuleKey("module:BentoBox-1"))
        #expect(!PositionStoreHygiene.isMisspelledPinnedModuleKey("module:Clock"))
        #expect(!PositionStoreHygiene.isMisspelledPinnedModuleKey("status:com.example.app::Item-0"))
        #expect(!PositionStoreHygiene.isMisspelledPinnedModuleKey("status:com.example.app::my-BentoBox-1"))
        #expect(!PositionStoreHygiene.isMisspelledPinnedModuleKey("status:com.example.app::com.apple.menuextra.controlcenter-BentoBox-"))
    }

    @Test("A misspelled key is pruned on the first pass, with nothing else")
    func prunedWithoutASecondLaunch() throws {
        let suite = "MisspelledPinnedModuleKeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var removed = Set<String>()

        let pruned = PositionStoreHygiene.prune(
            positions: [stale: 300, "module:BentoBox-1": 40, "module:Clock": 0],
            defaults: defaults
        ) { removed = $0 }

        #expect(pruned == [stale])
        #expect(removed == [stale])
    }
}
