//
//  GroupInterleavingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// A group is interleaved when another item's weight lies strictly between its lowest and highest member.
struct GroupInterleavingTests {
    private func interleaved(
        _ groups: [[String]],
        inScope: [String],
        _ weights: [String: Int]
    ) -> Bool {
        GroupInterleaving.isInterleaved(groups: groups, inScope: Set(inScope), weightByIdentifier: weights)
    }

    @Test("Members side by side are not interleaved")
    func contiguousGroup() {
        let weights = ["a1": 10, "a2": 11, "b": 20]
        #expect(!interleaved([["a1", "a2"]], inScope: ["a1", "a2", "b"], weights))
    }

    @Test("Another app's item between two members is an interloper")
    func interloperBetweenMembers() {
        let weights = ["a1": 10, "b": 11, "a2": 12]
        #expect(interleaved([["a1", "a2"]], inScope: ["a1", "a2", "b"], weights))
    }

    @Test("An item at the same weight as the lowest or highest member is not between them")
    func equalWeightsAreOutside() {
        #expect(!interleaved([["a1", "a2"]], inScope: ["a1", "a2"], ["a1": 10, "a2": 12, "b": 10]))
        #expect(!interleaved([["a1", "a2"]], inScope: ["a1", "a2"], ["a1": 10, "a2": 12, "b": 12]))
    }

    @Test("A group with fewer than two weighted members cannot be interleaved")
    func fewerThanTwoWeightedMembers() {
        let weights = ["a1": 10, "b": 11]
        #expect(!interleaved([["a1", "a2"]], inScope: ["a1", "a2", "b"], weights))
        #expect(!interleaved([["a1"]], inScope: ["a1", "b"], weights))
    }

    @Test("A group with no member in the order being applied is ignored")
    func groupOutOfScope() {
        let weights = ["a1": 10, "b": 11, "a2": 12]
        #expect(!interleaved([["a1", "a2"]], inScope: ["b"], weights))
        #expect(interleaved([["a1", "a2"]], inScope: ["a2"], weights))
    }

    @Test("Members of another group between the first group's members still count")
    func otherGroupMembersCount() {
        let weights = ["a1": 10, "b1": 11, "a2": 12, "b2": 13]
        #expect(interleaved([["a1", "a2"], ["b1", "b2"]], inScope: ["a1", "a2", "b1", "b2"], weights))
    }

    @Test("One interleaved group is enough, whichever group comes first")
    func laterGroupCanBeTheInterleavedOne() {
        let weights = ["a1": 10, "a2": 11, "b1": 20, "c": 21, "b2": 22]
        let order = ["a1", "a2", "b1", "b2", "c"]
        #expect(interleaved([["a1", "a2"], ["b1", "b2"]], inScope: order, weights))
    }

    @Test("No groups or no weights are not interleaved")
    func emptyInputs() {
        #expect(!interleaved([], inScope: ["a"], ["a": 1, "b": 2]))
        #expect(!interleaved([["a", "b"]], inScope: ["a", "b"], [:]))
    }
}
