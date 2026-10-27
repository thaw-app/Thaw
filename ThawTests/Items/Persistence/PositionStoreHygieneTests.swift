//
//  PositionStoreHygieneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Store hygiene prunes keys of uninstalled owners only after a second opinion")
struct PositionStoreHygieneTests {
    private let suites = ScratchSuites(prefix: "PositionStoreHygieneTests")

    /// A bundle identifier nothing on the machine has.
    private let gone = "status:com.example.thaw-tests.uninstalled-\(UUID().uuidString)::Item-0"

    @Test("An uninstalled owner's key waits one pass, then is pruned")
    func uninstalledOwnerNeedsTwoPasses() throws {
        let defaults = try #require(suites.make())
        let positions = [gone: 120]
        var removals: [Set<String>] = []

        let first = PositionStoreHygiene.prune(positions: positions, defaults: defaults) { removals.append($0) }
        #expect(first.isEmpty)
        #expect(removals.isEmpty)

        let second = PositionStoreHygiene.prune(positions: positions, defaults: defaults) { removals.append($0) }
        #expect(second == [gone])
        #expect(removals == [[gone]])
    }

    @Test("A key that comes back owned is forgotten as a candidate")
    func candidateIsForgottenWhenOwned() throws {
        let defaults = try #require(suites.make())
        var removed = false

        PositionStoreHygiene.prune(positions: [gone: 1], defaults: defaults) { _ in removed = true }
        // The key left the store before the second pass, so nothing is removed.
        PositionStoreHygiene.prune(positions: [:], defaults: defaults) { _ in removed = true }
        PositionStoreHygiene.prune(positions: [gone: 1], defaults: defaults) { _ in removed = true }

        #expect(!removed)
    }

    @Test("Apple, Thaw, display-name, running and installed owners are never pruned")
    func protectedOwnersAreKept() throws {
        let defaults = try #require(suites.make())
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw"
        let positions = [
            "status:com.apple.Siri::Item-0": 1,
            "status:com.stonerl.Thaw::Thaw.ControlItem.Hidden": 2,
            "status:iStatMenusMenubar::Item-0": 3,
            "status:\(ownBundle)::Item-0": 4,
            "status:com.apple.finder::Item-0": 5,
            "module:Clock": 6,
            "not a status key": 7,
        ]
        var removed = false

        for _ in 0 ..< 2 {
            let pruned = PositionStoreHygiene.prune(positions: positions, defaults: defaults) { _ in removed = true }
            #expect(pruned.isEmpty)
        }
        #expect(!removed)
    }
}
