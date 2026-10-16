//
//  ReturnAnchorsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `LayoutSolver.returnAnchors`, which picks the neighbors a
/// temporarily shown item is anchored against when it is returned to its
/// section.
///
/// Items arrive in WindowServer order, not left-to-right, so a new window can
/// sit next to any item, including one that can never be hidden. Anchoring to
/// it strands the item in that neighbor's section (#859), so the scan skips
/// ineligible neighbors while preferring the nearest eligible one.
@Suite("Return anchor selection")
struct ReturnAnchorsTests {
    // MARK: - Neighbor preference

    @Test("Both sides eligible yields the immediate neighbors")
    func immediateNeighborsOnBothSides() {
        let result = LayoutSolver.returnAnchors(
            forIndex: 2,
            itemCount: 5,
            eligibleIndices: [0, 1, 3, 4]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: 3, predecessor: 1))
    }

    @Test("The first position has no predecessor")
    func firstIndexHasNoPredecessor() {
        let result = LayoutSolver.returnAnchors(
            forIndex: 0,
            itemCount: 3,
            eligibleIndices: [0, 1, 2]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: 1, predecessor: nil))
    }

    @Test("The last position has no successor")
    func lastIndexHasNoSuccessor() {
        let result = LayoutSolver.returnAnchors(
            forIndex: 2,
            itemCount: 3,
            eligibleIndices: [0, 1, 2]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: nil, predecessor: 1))
    }

    // MARK: - Ineligible neighbors (#859)

    @Test("An ineligible successor is skipped, not used as the anchor")
    func skipsIneligibleSuccessor() {
        // The #859 state: the adjacent item is a Control Center module that
        // can never be hidden, so the scan has to continue outward instead
        // of returning the item into the visible section.
        let result = LayoutSolver.returnAnchors(
            forIndex: 0,
            itemCount: 4,
            eligibleIndices: [2, 3]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: 2, predecessor: nil))
    }

    @Test("An ineligible predecessor is skipped the same way")
    func skipsIneligiblePredecessor() {
        let result = LayoutSolver.returnAnchors(
            forIndex: 3,
            itemCount: 4,
            eligibleIndices: [0]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: nil, predecessor: 0))
    }

    @Test("No eligible neighbor on either side yields no anchors")
    func noEligibleNeighbors() {
        // Sends the caller to the section boundary instead.
        let result = LayoutSolver.returnAnchors(
            forIndex: 1,
            itemCount: 3,
            eligibleIndices: []
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: nil, predecessor: nil))
    }

    @Test("The item is never its own anchor")
    func itemIsNotItsOwnAnchor() {
        // The moving item is in its section, so it is in the eligible set.
        let result = LayoutSolver.returnAnchors(
            forIndex: 1,
            itemCount: 3,
            eligibleIndices: [1]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: nil, predecessor: nil))
    }

    // MARK: - Bounds

    @Test("An out-of-bounds index yields no anchors instead of trapping")
    func outOfBoundsIndexYieldsNoAnchors() {
        let result = LayoutSolver.returnAnchors(
            forIndex: 7,
            itemCount: 3,
            eligibleIndices: [0, 1, 2]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: nil, predecessor: nil))
    }

    @Test("A single-item list has no neighbors at all")
    func singleItemList() {
        let result = LayoutSolver.returnAnchors(
            forIndex: 0,
            itemCount: 1,
            eligibleIndices: [0]
        )

        #expect(result == LayoutSolver.ReturnAnchors(successor: nil, predecessor: nil))
    }
}
