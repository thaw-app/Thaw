//
//  MenuBarLeadingEdgeGeometryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

struct MenuBarLeadingEdgeGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let items = [CGRect(x: 100, y: 3, width: 100, height: 24), CGRect(x: 200, y: 3, width: 100, height: 24)]
    private let stable = CGRect(x: 90, y: 0, width: 220, height: 30)

    @Test(arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func visibleSectionEdgeCannotCutARevealedPill(section: MenuBarSectionName) {
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: 210, screenFrame: screen), itemBounds: items,
            stableTrailingBounds: stable, screenFrame: screen, revealedSection: section
        )
        #expect(updated.itemBounds == items)
        #expect(updated.stableTrailingBounds == stable)
    }

    @Test("Displays with overlapping x ranges must not share an edge")
    func verticallyStackedDisplayKeepsItsOwnGeometry() {
        let otherScreen = CGRect(x: 0, y: 800, width: 1000, height: 800)
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: 210, screenFrame: otherScreen), itemBounds: items,
            stableTrailingBounds: stable, screenFrame: screen, revealedSection: nil
        )
        #expect(updated.itemBounds == items)
        #expect(updated.stableTrailingBounds == stable)
    }

    @Test("A conceal transition keeps its settle window even after revealedSection clears")
    func transitionDoesNotTrimFadingItems() {
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: 210, screenFrame: screen), itemBounds: items,
            stableTrailingBounds: stable, screenFrame: screen, revealedSection: nil,
            isTransitioning: true
        )
        #expect(updated.itemBounds == items)
        #expect(updated.stableTrailingBounds == stable)
    }

    @Test("A known mirrored source still cannot trim revealed or transitioning geometry", arguments: [false, true])
    func mirroredEdgeRespectsTransitions(transitioning: Bool) {
        let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: 1210, screenFrame: source), itemBounds: items,
            stableTrailingBounds: stable, screenFrame: screen,
            revealedSection: transitioning ? nil : .hidden,
            isTransitioning: transitioning, sourceScreenFrame: source
        )
        #expect(updated.itemBounds == items)
        #expect(updated.stableTrailingBounds == stable)
    }

    @Test("A mirrored pill ignores edges from a different source display")
    func unrelatedSourceDoesNotMoveMirroredPill() {
        let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let unrelated = CGRect(x: 2000, y: 0, width: 1000, height: 800)
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: 2210, screenFrame: unrelated), itemBounds: items,
            stableTrailingBounds: stable, screenFrame: screen, revealedSection: nil,
            sourceScreenFrame: source
        )
        #expect(updated.itemBounds == items)
        #expect(updated.stableTrailingBounds == stable)
    }

    @Test(arguments: [CGFloat(80), CGFloat(210)])
    func concealedPillStillFollowsItsOwnVisibleEdge(edge: CGFloat) {
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: edge, screenFrame: screen), itemBounds: items,
            stableTrailingBounds: stable, screenFrame: screen, revealedSection: nil
        )
        #expect(updated.itemBounds.map(\.minX).min() == edge)
        #expect(updated.stableTrailingBounds.minX == edge - 10)
        #expect(updated.stableTrailingBounds.maxX == stable.maxX)
    }
}
