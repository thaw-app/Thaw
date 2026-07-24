//
//  AXIdentityCatalogTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Covers the pure, non-AX helpers `AXIdentityCatalog` and
/// `MenuBarItemManager.ControlItemPair` use for frame correlation. Taking a
/// live AX snapshot (walking a real `extrasMenuBar`) requires the
/// Accessibility permission (TCC) and a real menu bar, so it is not
/// unit-testable in CI and is intentionally not scaffolded here.
final class AXIdentityCatalogTests: XCTestCase {
    // MARK: - AXIdentityCatalog.identity(for:in:)

    private func identity(frame: CGRect) -> AXIdentityCatalog.AXItemIdentity {
        AXIdentityCatalog.AXItemIdentity(identifier: nil, title: nil, help: nil, frame: frame)
    }

    func testIdentityReturnsExactOverlapWinner() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let exact = identity(frame: target)
        let distant = identity(frame: CGRect(x: 500, y: 500, width: 20, height: 20))

        let result = AXIdentityCatalog.identity(for: target, in: [distant, exact])

        XCTAssertEqual(result?.frame, target)
    }

    func testIdentityRequiresMoreThanHalfOfSmallerRectArea() {
        // Both rects have area 100 (so "smaller" area is 100). A 60-area
        // intersection (60%) clears the >50% threshold.
        let target = CGRect(x: 0, y: 0, width: 10, height: 10)
        let candidate = identity(frame: CGRect(x: 4, y: 0, width: 10, height: 10))

        let result = AXIdentityCatalog.identity(for: target, in: [candidate])

        XCTAssertNotNil(result)
    }

    func testIdentityRejectsOverlapAtOrBelowHalfOfSmallerRectArea() {
        // Both rects have area 100 (so "smaller" area is 100). A 50-area
        // intersection is exactly the threshold, which the spec requires
        // to be exceeded, not merely met.
        let target = CGRect(x: 0, y: 0, width: 10, height: 10)
        let candidate = identity(frame: CGRect(x: 5, y: 0, width: 10, height: 10))

        let result = AXIdentityCatalog.identity(for: target, in: [candidate])

        XCTAssertNil(result)
    }

    func testIdentityReturnsNilOnTieBetweenTopCandidates() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        // Two distinct candidates, each fully containing target so both
        // clear the threshold with the exact same intersection area (the
        // full 400pt² of target) — an ambiguous tie.
        let exact = identity(frame: target)
        let taller = identity(frame: CGRect(x: 0, y: 0, width: 20, height: 30))

        let result = AXIdentityCatalog.identity(for: target, in: [exact, taller])

        XCTAssertNil(result)
    }

    func testIdentityReturnsNilForDisjointFrames() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let disjoint = identity(frame: CGRect(x: 1000, y: 1000, width: 20, height: 20))

        let result = AXIdentityCatalog.identity(for: target, in: [disjoint])

        XCTAssertNil(result)
    }

    func testIdentityReturnsNilForEmptySnapshot() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)

        let result = AXIdentityCatalog.identity(for: target, in: [])

        XCTAssertNil(result)
    }

    func testIdentityTakesHighestOverlapAmongMultipleCandidates() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let partial = identity(frame: CGRect(x: 15, y: 0, width: 20, height: 20)) // small overlap, below threshold
        let full = identity(frame: target) // full overlap

        let result = AXIdentityCatalog.identity(for: target, in: [partial, full])

        XCTAssertEqual(result?.frame, target)
    }

    // MARK: - MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates:axFrames:)

    private typealias CandidateFrame = MenuBarItemManager.ControlItemPair.CandidateFrame

    func testSelectViaAXFrameMatchesHiddenAndAlwaysHiddenAmongDistractors() {
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let alwaysHiddenFrame = CGRect(x: 200, y: 0, width: 20, height: 20)

        let candidates = [
            CandidateFrame(index: 0, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), isOwnProcess: false), // distractor, third-party
            CandidateFrame(index: 1, bounds: hiddenFrame, isOwnProcess: true),
            CandidateFrame(index: 2, bounds: CGRect(x: 300, y: 0, width: 20, height: 20), isOwnProcess: false), // distractor
            CandidateFrame(index: 3, bounds: alwaysHiddenFrame, isOwnProcess: true),
        ]
        let axFrames = [hiddenFrame, alwaysHiddenFrame]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: axFrames)

        XCTAssertEqual(result, [1, 3])
    }

    func testSelectViaAXFrameToleratesSmallFrameOffsets() {
        // AX-reported frame is a few points off from the CG window bounds.
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let axHiddenFrame = CGRect(x: 102, y: 1, width: 20, height: 20)

        let candidates = [
            CandidateFrame(index: 0, bounds: hiddenFrame, isOwnProcess: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [axHiddenFrame])

        XCTAssertEqual(result, [0])
    }

    func testSelectViaAXFrameIgnoresThirdPartyCandidatesEvenOnFrameMatch() {
        let frame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let candidates = [
            CandidateFrame(index: 0, bounds: frame, isOwnProcess: false),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [frame])

        XCTAssertNil(result)
    }

    func testSelectViaAXFrameReturnsOnlyHiddenWhenNoSecondMatch() {
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let candidates = [
            CandidateFrame(index: 0, bounds: hiddenFrame, isOwnProcess: true),
            CandidateFrame(index: 1, bounds: CGRect(x: 999, y: 999, width: 20, height: 20), isOwnProcess: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [hiddenFrame])

        XCTAssertEqual(result, [0])
    }

    func testSelectViaAXFrameReturnsNilWhenNoCandidateCorrelates() {
        let candidates = [
            CandidateFrame(index: 0, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), isOwnProcess: true),
        ]
        let axFrames = [CGRect(x: 500, y: 500, width: 20, height: 20)]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: axFrames)

        XCTAssertNil(result)
    }
}
