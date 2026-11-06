//
//  PositionStoreHygieneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
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

    @Test("Apple, Thaw, display-name, module and malformed keys are never pruned")
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

    @Test("A running or installed owner keeps its key, and the same owner gone is pruned")
    func runningAndInstalledOwnersAreKept() throws {
        let key = "status:com.example.thaw-tests.owner::Item-0"
        var pruned: [[String]] = []
        for (running, installed) in [(true, false), (false, true), (false, false)] {
            let defaults = try #require(suites.make())
            for _ in 0 ..< 2 {
                pruned.append(PositionStoreHygiene.prune(
                    positions: [key: 1],
                    defaults: defaults,
                    liveOwners: running ? ["com.example.thaw-tests.owner"] : [],
                    isInstalled: { _ in installed }
                ) { _ in })
            }
        }
        #expect(pruned == [[], [], [], [], [], [key]])
    }

    @Test("Pruning the store removes doomed keys from a fresh read and keeps every other weight")
    func pruneCurrentStoreWritesTheFreshRead() throws {
        let defaults = try #require(suites.make())
        let misspelled = "module:com.apple.menuextra.controlcenter-BentoBox-12"
        let fake = FakeStore(reads: [
            [misspelled: 1, "module:Clock": 2],
            // The host moved Clock between the two reads.
            [misspelled: 1, "module:Clock": 9],
        ])

        PositionStoreHygiene.pruneCurrentStore(
            permit: .unsequenced("hygiene test"),
            store: PermittedPositionStore(wrapping: fake),
            defaults: defaults
        )

        #expect(fake.writes == [["module:Clock": 9]])
    }

    @Test("An empty re-read is treated as a failed read and nothing is written")
    func emptyReReadWritesNothing() throws {
        let defaults = try #require(suites.make())
        let fake = FakeStore(reads: [["module:com.apple.menuextra.controlcenter-BentoBox-12": 1], [:]])

        PositionStoreHygiene.pruneCurrentStore(
            permit: .unsequenced("hygiene test"),
            store: PermittedPositionStore(wrapping: fake),
            defaults: defaults
        )

        #expect(fake.writes.isEmpty)
    }
}

/// Answers each read with the next table in line and records every write.
@MainActor
private final class FakeStore: MenuBarPositionStoring {
    private var reads: [[String: Int]]
    private(set) var writes: [[String: Int]] = []

    init(reads: [[String: Int]]) {
        self.reads = reads
    }

    func readPositions() -> [String: Int] {
        reads.isEmpty ? [:] : reads.removeFirst()
    }

    func currentPositions() -> [String: Int] {
        [:]
    }

    func writePositions(_ positions: [String: Int]) {
        writes.append(positions)
    }

    func resolveKey(
        for _: MenuBarItem, existingKeys _: [String], positions _: [String: Int], liveItems _: [MenuBarItem]
    ) -> String? {
        nil
    }

    func parseStatusKey(_: String) -> PositionStatusKey? {
        nil
    }

    func isParkedWeight(_: Int) -> Bool {
        false
    }

    func isProvenAbsent(_: String) -> Bool {
        false
    }

    func move(
        item _: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool
    ) -> Bool {
        false
    }

    func applyOrder(desiredOrder _: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        []
    }

    func respaceOrder(desiredOrder _: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        []
    }

    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func applyControlItemOrder(desiredOrder _: [MenuBarItem], opaqueVisibleKeys _: [String], liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func recordAbsenceEvidence(seen _: Set<String>, blank _: Set<String>) -> Set<String> {
        []
    }

    func resetAbsenceEvidence() {}
}
