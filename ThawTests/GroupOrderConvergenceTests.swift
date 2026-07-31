//
//  GroupOrderConvergenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
@testable import Thaw
import XCTest

/// Guards the write-storm hazard around `savedSectionOrder`.
///
/// That dictionary has two writers: `MenuBarSectionController` mirrors its
/// already-gathered order in via `mirrorMacOS27SectionOrder`, and the cache
/// cycle pushes `computeSectionOrder`'s output in. The cycle only writes when
/// `mirrored != savedSectionOrder`, and each write schedules an overflow
/// rebalance that re-enters the cycle — so if the two sides disagree on every
/// pass, the guard never fires and it writes forever. That is the shape of
/// commit `2e38d6c6` ("stop the macOS 27 reorder storm").
///
/// Convergence therefore requires the cycle's transform to be a **fixpoint**
/// over an order the controller has already gathered. These tests model that
/// seam with the two pure functions that compose to make it:
/// `LayoutSolver.planSectionOrder` (the merge) then
/// `MenuBarItemGroupPolicy.gather` (the canonicalization).
final class GroupOrderConvergenceTests: XCTestCase {
    private typealias Policy = MenuBarItemGroupPolicy

    /// One cache cycle's transform for a single section.
    private func cycle(
        live: [String],
        saved: [String],
        groups: Policy.GroupSet
    ) -> [String] {
        let merged = LayoutSolver.planSectionOrder(
            currentInSection: live,
            oldSavedForSection: saved,
            allCurrentIdentifiers: Set(live),
            allCurrentBaseIdentifiers: Set(live),
            allCurrentNamespaces: []
        )
        return Policy.gather(groups: groups, in: merged).order
    }

    /// The core guarantee: once the controller has gathered a section, the
    /// cache cycle must reproduce that exact array, so the equality guard
    /// short-circuits and nothing is written.
    func testCycleIsAFixpointOverAGatheredOrder() {
        let groups = Policy.GroupSet(groups: [["g1", "g2"]])
        // What the controller committed and mirrored in.
        let saved = ["a", "g1", "g2", "b"]
        // What AX actually reports, with the group scattered.
        let live = ["a", "g1", "b", "g2"]

        let first = cycle(live: live, saved: saved, groups: groups)
        XCTAssertEqual(first, saved, "one cycle did not reproduce the gathered order")

        let second = cycle(live: live, saved: first, groups: groups)
        XCTAssertEqual(second, first, "a second cycle changed the order again")
    }

    /// Without the gather step the two sides disagree forever — this is the
    /// failure the test above is protecting against, pinned so the protection
    /// cannot be quietly removed.
    func testWithoutGatheringTheCycleNeverConverges() {
        let saved = ["a", "g1", "g2", "b"]
        let live = ["a", "g1", "b", "g2"]

        let ungathered = LayoutSolver.planSectionOrder(
            currentInSection: live,
            oldSavedForSection: saved,
            allCurrentIdentifiers: Set(live),
            allCurrentBaseIdentifiers: Set(live),
            allCurrentNamespaces: []
        )

        XCTAssertNotEqual(
            ungathered,
            saved,
            "if this ever passes, gathering is no longer needed for convergence"
        )
    }

    /// A closed app's saved entry can be spliced *inside* a group's run by
    /// `planSectionOrder`'s anchor scan. Gathering afterwards pushes it back
    /// out, so the result is still canonical and still a fixpoint.
    func testClosedAppSplicedIntoAGroupSpanIsPushedOutAndConverges() {
        let groups = Policy.GroupSet(groups: [["g1", "g2"]])
        // "gone" is not in the live set, so it is a closed-app entry.
        let saved = ["g1", "gone", "g2", "b"]
        let live = ["g1", "g2", "b"]

        let first = cycle(live: live, saved: saved, groups: groups)
        XCTAssertTrue(first.contains("gone"), "closed-app entry must be preserved")
        XCTAssertEqual(
            Policy.scattered(groups: groups, in: first),
            [],
            "group left scattered after the merge"
        )

        let second = cycle(live: live, saved: first, groups: groups)
        XCTAssertEqual(second, first, "did not settle after one pass")
    }

    func testNoGroupsMeansTheCycleIsUnchangedFromToday() {
        let saved = ["a", "b", "c"]
        let live = ["a", "b", "c"]

        XCTAssertEqual(cycle(live: live, saved: saved, groups: .empty), saved)
    }

    /// Convergence must not depend on the group happening to be adjacent in
    /// the live order — that is the whole point of gathering.
    func testConvergesFromAnyLiveScatter() {
        let groups = Policy.GroupSet(groups: [["g1", "g2", "g3"]])
        let scatters = [
            ["g1", "x", "g2", "y", "g3"],
            ["x", "g3", "g1", "y", "g2"],
            ["g1", "g2", "g3", "x", "y"],
        ]

        for live in scatters {
            let first = cycle(live: live, saved: [], groups: groups)
            let second = cycle(live: live, saved: first, groups: groups)
            XCTAssertEqual(second, first, "did not settle for live order \(live)")
            XCTAssertEqual(
                Policy.scattered(groups: groups, in: second),
                [],
                "group still scattered for live order \(live)"
            )
        }
    }
}
