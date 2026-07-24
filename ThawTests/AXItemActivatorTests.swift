//
//  AXItemActivatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Covers the pure, non-AX helpers `AXItemActivator` uses to pick a
/// candidate element and verify its frame. The AX round trip itself
/// (hit-testing, `performAction`, actually resolving a live `UIElement`)
/// requires the Accessibility permission (TCC) and a real menu bar item, so
/// it is not unit-testable in CI and is intentionally not scaffolded here.
final class AXItemActivatorTests: XCTestCase {
    // MARK: - candidateIndex(inFrames:containing:)

    func testCandidateIndexReturnsFrameContainingPoint() {
        let point = CGPoint(x: 50, y: 50)
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 40, y: 40, width: 20, height: 20),
            CGRect(x: 100, y: 100, width: 10, height: 10),
        ]

        let index = AXItemActivator.candidateIndex(inFrames: frames, containing: point)

        XCTAssertEqual(index, 1)
    }

    func testCandidateIndexReturnsFirstMatchWhenMultipleContainPoint() {
        let point = CGPoint(x: 5, y: 5)
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 0, y: 0, width: 20, height: 20),
        ]

        let index = AXItemActivator.candidateIndex(inFrames: frames, containing: point)

        XCTAssertEqual(index, 0)
    }

    func testCandidateIndexReturnsNilWhenNoFrameContainsPoint() {
        let point = CGPoint(x: 500, y: 500)
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 40, y: 40, width: 20, height: 20),
        ]

        let index = AXItemActivator.candidateIndex(inFrames: frames, containing: point)

        XCTAssertNil(index)
    }

    func testCandidateIndexReturnsNilForEmptyFrameList() {
        let index = AXItemActivator.candidateIndex(inFrames: [], containing: .zero)

        XCTAssertNil(index)
    }

    // MARK: - framesMatch(_:_:tolerance:)

    func testFramesMatchWhenIdentical() {
        let frame = CGRect(x: 10, y: 10, width: 20, height: 20)

        XCTAssertTrue(AXItemActivator.framesMatch(frame, frame, tolerance: 0))
    }

    func testFramesMatchWhenOverlapping() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        let target = CGRect(x: 10, y: 10, width: 20, height: 20)

        XCTAssertTrue(AXItemActivator.framesMatch(candidate, target, tolerance: 0))
    }

    func testFramesMatchWithinTolerancePasses() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        // Just outside candidate's bounds, but within the tolerance expansion.
        let target = CGRect(x: 22, y: 0, width: 10, height: 10)

        XCTAssertTrue(AXItemActivator.framesMatch(candidate, target, tolerance: 5))
    }

    func testFramesMismatchWhenDisjointBeyondTolerance() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        let target = CGRect(x: 100, y: 100, width: 20, height: 20)

        XCTAssertFalse(AXItemActivator.framesMatch(candidate, target, tolerance: 5))
    }

    func testFramesMismatchWhenJustOutsideTolerance() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        // 6pt gap on the x-axis, tolerance only covers 5pt.
        let target = CGRect(x: 26, y: 0, width: 10, height: 10)

        XCTAssertFalse(AXItemActivator.framesMatch(candidate, target, tolerance: 5))
    }
}
