//
//  AXItemActivatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers the pure, non-AX helpers `AXItemActivator` uses to pick a
/// candidate element and verify its frame. The AX round trip itself
/// (hit-testing, `performAction`, actually resolving a live `UIElement`)
/// requires the Accessibility permission (TCC) and a real menu bar item, so
/// it is not unit-testable in CI and is intentionally not scaffolded here.
@Suite("AX item activator helpers")
struct AXItemActivatorTests {
    // MARK: - candidateIndex(inFrames:containing:)

    @Test("The candidate index is the frame containing the point")
    func candidateIndexReturnsFrameContainingPoint() {
        let point = CGPoint(x: 50, y: 50)
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 40, y: 40, width: 20, height: 20),
            CGRect(x: 100, y: 100, width: 10, height: 10),
        ]

        let index = AXItemActivator.candidateIndex(inFrames: frames, containing: point)

        #expect(index == 1)
    }

    @Test("The first match wins when several frames contain the point")
    func candidateIndexReturnsFirstMatchWhenMultipleContainPoint() {
        let point = CGPoint(x: 5, y: 5)
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 0, y: 0, width: 20, height: 20),
        ]

        let index = AXItemActivator.candidateIndex(inFrames: frames, containing: point)

        #expect(index == 0)
    }

    @Test("No frame containing the point yields nil")
    func candidateIndexReturnsNilWhenNoFrameContainsPoint() {
        let point = CGPoint(x: 500, y: 500)
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 40, y: 40, width: 20, height: 20),
        ]

        let index = AXItemActivator.candidateIndex(inFrames: frames, containing: point)

        #expect(index == nil)
    }

    @Test("An empty frame list yields nil")
    func candidateIndexReturnsNilForEmptyFrameList() {
        let index = AXItemActivator.candidateIndex(inFrames: [], containing: .zero)

        #expect(index == nil)
    }

    // MARK: - framesMatch(_:_:tolerance:)

    @Test("Identical frames match")
    func framesMatchWhenIdentical() {
        let frame = CGRect(x: 10, y: 10, width: 20, height: 20)

        #expect(AXItemActivator.framesMatch(frame, frame, tolerance: 0))
    }

    @Test("Overlapping frames match")
    func framesMatchWhenOverlapping() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        let target = CGRect(x: 10, y: 10, width: 20, height: 20)

        #expect(AXItemActivator.framesMatch(candidate, target, tolerance: 0))
    }

    @Test("A frame inside the tolerance expansion matches")
    func framesMatchWithinTolerancePasses() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        // Just outside candidate's bounds, but within the tolerance expansion.
        let target = CGRect(x: 22, y: 0, width: 10, height: 10)

        #expect(AXItemActivator.framesMatch(candidate, target, tolerance: 5))
    }

    @Test("Frames disjoint well beyond the tolerance do not match")
    func framesMismatchWhenDisjointBeyondTolerance() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        let target = CGRect(x: 100, y: 100, width: 20, height: 20)

        #expect(!AXItemActivator.framesMatch(candidate, target, tolerance: 5))
    }

    @Test("A frame just outside the tolerance does not match")
    func framesMismatchWhenJustOutsideTolerance() {
        let candidate = CGRect(x: 0, y: 0, width: 20, height: 20)
        // 6pt gap on the x-axis, tolerance only covers 5pt.
        let target = CGRect(x: 26, y: 0, width: 10, height: 10)

        #expect(!AXItemActivator.framesMatch(candidate, target, tolerance: 5))
    }
}
