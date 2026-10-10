//
//  SectionMovePlanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("macOS 27 section move planning")
@MainActor
struct SectionMovePlanTests {
    private typealias Move = MenuBarItemManager.PlannedSectionMove

    @Test("Section restores compare live geometry with authored order", arguments: MenuBarSection.Name.allCases)
    func revealedHiddenOrderPlansFromLiveGeometry(section: MenuBarSection.Name) {
        let codex = item("CodexBar", x: 0)
        let proton = item("ProtonDrive", x: 24)
        let desired = [proton, codex].map(\.uniqueIdentifier)

        // The segmenter may return desired order; LCS must compare live geometry or visibility toggles can reverse the Hidden row.
        let moves = MenuBarItemManager.planSectionMoves(
            items: [proton, codex], // Enumeration order is not visual order.
            desiredOrder: desired,
            section: section,
            experimentalSystemItemHiding: false
        )
        #expect(moves.count == 1)

        // Verify the resulting displayed order, not just the presence of planned moves.
        var live = [codex, proton].map(\.uniqueIdentifier)
        for move in moves {
            live.removeAll { $0 == move.uid }
            switch move.destination {
            case let .leftOfUID(anchor):
                guard let index = live.firstIndex(of: anchor) else {
                    Issue.record("Missing left anchor")
                    return
                }
                live.insert(move.uid, at: index)
            case let .rightOfUID(anchor):
                guard let index = live.firstIndex(of: anchor) else {
                    Issue.record("Missing right anchor")
                    return
                }
                live.insert(move.uid, at: index + 1)
            case .sectionBoundary:
                Issue.record("A within-section reorder must not need a divider")
                return
            }
        }
        #expect(live == desired)
    }

    @Test("A live bar that already matches the layout needs no moves")
    func matchingLiveGeometryNeedsNoMoves() {
        let a = item("a", x: 0)
        let b = item("b", x: 24)
        let moves = MenuBarItemManager.planSectionMoves(
            items: [b, a],
            desiredOrder: [a, b].map(\.uniqueIdentifier),
            section: .hidden,
            experimentalSystemItemHiding: false
        )
        #expect(moves.isEmpty)
    }

    @Test("Live planning keeps fixed system anchors between independent segments")
    func liveGeometryRespectsFixedAnchors() {
        let a = item("a", x: 0)
        let b = item("b", x: 48)
        let c = item("c", x: 72)
        let clock = MenuBarItem(
            tag: .clock,
            windowID: 25,
            ownerPID: 0,
            sourcePID: nil,
            bounds: CGRect(x: 24, y: 0, width: 24, height: 24),
            title: "Clock",
            isOnScreen: true
        )
        let moves = MenuBarItemManager.planSectionMoves(
            items: [c, clock, a, b],
            desiredOrder: [c, a, b].map(\.uniqueIdentifier),
            section: .visible,
            experimentalSystemItemHiding: false
        )
        #expect(moves.count == 1)
        #expect(moves.allSatisfy { move in
            guard [b.uniqueIdentifier, c.uniqueIdentifier].contains(move.uid) else { return false }
            switch move.destination {
            case let .leftOfUID(anchor), let .rightOfUID(anchor):
                return [b.uniqueIdentifier, c.uniqueIdentifier].contains(anchor)
            case .sectionBoundary:
                return false
            }
        })
    }

    @Test("One displaced item yields one LCS move, not a bubble pass")
    func displacedItemMovesAlone() {
        let moves = MenuBarItemManager.planSectionMoves(
            segments: [["a", "x", "b", "c", "d"]],
            desiredOrder: ["a", "b", "c", "d", "x"],
            section: .visible
        )
        #expect(moves == [Move(uid: "x", destination: .rightOfUID("d"))])
    }

    @Test("Segments are planned independently and never cross each other")
    func segmentsPlanIndependently() {
        let moves = MenuBarItemManager.planSectionMoves(
            segments: [["b", "a"], ["d", "c"]],
            desiredOrder: ["a", "b", "c", "d"],
            section: .hidden
        )
        #expect(moves.count == 2)
        #expect(moves.allSatisfy { ["a", "b"].contains($0.uid) || ["c", "d"].contains($0.uid) })
    }

    @Test("Identifiers outside the segment are not planned for")
    func foreignDesiredIdentifiersAreIgnored() {
        let moves = MenuBarItemManager.planSectionMoves(
            segments: [["a", "b"]],
            desiredOrder: ["z", "a", "b", "y"],
            section: .visible
        )
        #expect(moves.isEmpty)
    }

    @Test("A preferred mover is the one dragged when two subsequences tie")
    func preferredMoverWins() {
        let moves = MenuBarItemManager.planSectionMoves(
            segments: [["a", "n", "b"]],
            desiredOrder: ["a", "b", "n"],
            section: .visible,
            preferredMoveUIDs: ["n"]
        )
        #expect(moves.map(\.uid) == ["n"])
    }

    @Test("A skipped cluster member cannot anchor a later move")
    func skippedClusterMemberInvalidatesDependentMove() {
        let a = item("a", namespace: "com.example.Cluster", x: 0)
        let b = item("b", namespace: "com.example.Cluster", x: 24)
        let c = item("c", namespace: "com.example.Other", x: 48)
        let moves = MenuBarItemManager.planSectionMoves(
            segments: [[a, b, c].map(\.uniqueIdentifier)],
            desiredOrder: [c, b, a].map(\.uniqueIdentifier),
            section: .visible
        )
        var execution = LayoutMoveSequenceExecution(moves: moves)

        // b trails a's cluster and is skipped; a must not use b's unverified slot as an anchor.
        let resolved = MenuBarItemManager.nextResolvedPlannedMove(
            from: &execution,
            in: [a, b, c],
            controlItems: nil
        )
        #expect(resolved == nil)
        #expect(execution.needsReplan)
        #expect(!execution.isComplete)
    }

    @Test("A vanished anchor invalidates dependents without blocking another segment")
    func missingAnchorPreservesIndependentMove() {
        let a = item("a", x: 0)
        let b = item("b", x: 24)
        let c = item("c", x: 48)
        let x = item("x", x: 72)
        let y = item("y", x: 96)
        let moves = MenuBarItemManager.planSectionMoves(
            segments: [[a, b, c].map(\.uniqueIdentifier), [x, y].map(\.uniqueIdentifier)],
            desiredOrder: [c, b, a, y, x].map(\.uniqueIdentifier),
            section: .visible
        )
        var execution = LayoutMoveSequenceExecution(moves: moves)
        let resolved = MenuBarItemManager.nextResolvedPlannedMove(
            from: &execution,
            in: [a, b, x, y], // c disappeared after planning.
            controlItems: nil
        )
        #expect(resolved?.item.uniqueIdentifier == x.uniqueIdentifier)
        #expect(resolved?.destination.targetItem.uniqueIdentifier == y.uniqueIdentifier)
        #expect(execution.needsReplan)
    }

    private func item(_ title: String, namespace: String? = nil, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(namespace ?? "com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}
