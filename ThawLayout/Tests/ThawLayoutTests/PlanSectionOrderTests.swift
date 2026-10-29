//
//  PlanSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
import ThawLayout

/// Characterization for LayoutSolver.planSectionOrder, checked against the original scan-based merge.
@Suite("planSectionOrder")
struct PlanSectionOrderTests {
    /// The merge as it was written before it was indexed, kept as the reference for output order.
    private static func referenceMerge(
        currentInSection: [String],
        oldSavedForSection: [String],
        allCurrentIdentifiers: Set<String>,
        allCurrentBaseIdentifiers: Set<String>,
        allCurrentNamespaces: Set<String>
    ) -> [String] {
        var identifiers = currentInSection
        for (oldIdx, savedUID) in oldSavedForSection.enumerated() {
            if identifiers.contains(savedUID) || allCurrentIdentifiers.contains(savedUID) {
                continue
            }
            let base = savedUID.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
            if allCurrentBaseIdentifiers.contains(base) {
                continue
            }
            if !allCurrentNamespaces.isEmpty {
                let namespace = savedUID.prefix { $0 != ":" }
                if !namespace.isEmpty, allCurrentNamespaces.contains(String(namespace)) {
                    continue
                }
            }
            var insertAt = identifiers.count
            var foundForward = false
            if oldIdx + 1 < oldSavedForSection.count {
                for candidate in oldSavedForSection[(oldIdx + 1)...] {
                    if let anchorIdx = identifiers.firstIndex(of: candidate) {
                        insertAt = anchorIdx
                        foundForward = true
                        break
                    }
                }
            }
            if !foundForward, oldIdx > 0 {
                for i in stride(from: oldIdx - 1, through: 0, by: -1) {
                    if let anchorIdx = identifiers.firstIndex(of: oldSavedForSection[i]) {
                        insertAt = anchorIdx + 1
                        break
                    }
                }
            }
            identifiers.insert(savedUID, at: insertAt)
        }
        return identifiers
    }

    /// A deterministic generator so a failing case can be replayed.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test("A closed app goes back before its closest present successor")
    func closedAppBeforeSuccessor() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["com.a:x:0", "com.c:x:0"],
            oldSavedForSection: ["com.a:x:0", "com.b:x:0", "com.c:x:0"],
            allCurrentIdentifiers: ["com.a:x:0", "com.c:x:0"],
            allCurrentBaseIdentifiers: ["com.a:x", "com.c:x"]
        )
        #expect(result == ["com.a:x:0", "com.b:x:0", "com.c:x:0"])
    }

    @Test("A closed app with no present successor goes after its closest present predecessor")
    func closedAppAfterPredecessor() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["com.c:x:0", "com.a:x:0"],
            oldSavedForSection: ["com.a:x:0", "com.b:x:0"],
            allCurrentIdentifiers: ["com.a:x:0", "com.c:x:0"],
            allCurrentBaseIdentifiers: ["com.a:x", "com.c:x"]
        )
        #expect(result == ["com.c:x:0", "com.a:x:0", "com.b:x:0"])
    }

    @Test("Moved items, stale instances and title variants are dropped")
    func dropsStaleEntries() {
        let result = LayoutSolver.planSectionOrder(
            currentInSection: ["com.a:x:0"],
            oldSavedForSection: ["com.moved:x:0", "com.a:x:1", "com.live:old", "com.closed:x:0"],
            allCurrentIdentifiers: ["com.a:x:0", "com.moved:x:0", "com.live:new"],
            allCurrentBaseIdentifiers: ["com.a:x", "com.moved:x", "com.live:new"],
            allCurrentNamespaces: ["com.a", "com.moved", "com.live"]
        )
        #expect(result == ["com.a:x:0", "com.closed:x:0"])
    }

    @Test("The indexed merge matches the original merge on random input", arguments: 0 ..< 400)
    func matchesReference(seed: Int) {
        var generator = SeededGenerator(state: UInt64(seed) &+ 0x9E37_79B9_7F4A_7C15)
        let pool = (0 ..< 14).map { "com.app\($0 % 9):item:\($0 % 3)" }
        func pick() -> String {
            pool[Int.random(in: 0 ..< pool.count, using: &generator)]
        }
        let current = (0 ..< Int.random(in: 0 ... 6, using: &generator)).map { _ in pick() }
        let saved = (0 ..< Int.random(in: 0 ... 12, using: &generator)).map { _ in pick() }
        let elsewhere = Set((0 ..< Int.random(in: 0 ... 3, using: &generator)).map { _ in pick() })
        let allCurrent = Set(current).union(elsewhere)
        let bases = Set((0 ..< Int.random(in: 0 ... 2, using: &generator)).map { _ in
            pick().split(separator: ":").prefix(2).joined(separator: ":")
        })
        let namespaces: Set<String> = Bool.random(using: &generator) ? ["com.app\(Int.random(in: 0 ..< 9, using: &generator))"] : []

        let expected = Self.referenceMerge(
            currentInSection: current,
            oldSavedForSection: saved,
            allCurrentIdentifiers: allCurrent,
            allCurrentBaseIdentifiers: bases,
            allCurrentNamespaces: namespaces
        )
        let actual = LayoutSolver.planSectionOrder(
            currentInSection: current,
            oldSavedForSection: saved,
            allCurrentIdentifiers: allCurrent,
            allCurrentBaseIdentifiers: bases,
            allCurrentNamespaces: namespaces
        )
        #expect(actual == expected, "current: \(current) saved: \(saved)")
    }

    @Test("A large saved order of closed apps merges quickly and keeps its order")
    func largeInputStaysFast() {
        let current = (0 ..< 200).map { "com.live\($0):item:0" }
        let closed = (0 ..< 20000).map { "com.closed\($0):item:0" }
        let start = ContinuousClock.now
        let result = LayoutSolver.planSectionOrder(
            currentInSection: current,
            oldSavedForSection: closed,
            allCurrentIdentifiers: Set(current),
            allCurrentBaseIdentifiers: []
        )
        let elapsed = ContinuousClock.now - start
        #expect(result == current + closed)
        #expect(elapsed < .seconds(2))
    }
}
