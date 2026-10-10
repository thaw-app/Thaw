//
//  AssistedPanelPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pointer-centered placement must stay on-screen and avoid covering the pointer when geometry allows.
@Suite("Assisted panel placement")
struct AssistedPanelPlacementTests {
    /// Large-screen fixture permits below-pointer placement without flipping or clamping.
    private static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private static let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 957)
    private static let size = CGSize(width: 680, height: 560)

    @Test("The panel hangs below the pointer when there is room")
    func hangsBelowPointer() {
        let pointer = CGPoint(x: 756, y: 600)
        let frame = AssistedPanelPlacement.frame(
            near: pointer, in: Self.visibleFrame, size: Self.size
        )

        #expect(frame.maxY < pointer.y)
        #expect(frame.midX == pointer.x)
    }

    @Test("The pointer is never inside the panel")
    func pointerNeverCovered() {
        // Test edges only: a 560-point panel cannot avoid a mid-screen pointer on a 957-point screen.
        // The roomier-side rule chooses which side receives unavoidable coverage.
        let pointers = [
            CGPoint(x: 10, y: 950),
            CGPoint(x: 1500, y: 950),
            CGPoint(x: 10, y: 5),
            CGPoint(x: 1500, y: 5),
        ]
        for pointer in pointers {
            let frame = AssistedPanelPlacement.frame(
                near: pointer, in: Self.visibleFrame, size: Self.size
            )
            #expect(
                !frame.contains(pointer),
                "Panel \(frame) covers the pointer at \(pointer)"
            )
        }
    }

    @Test("The panel flips above when there is no room underneath")
    func flipsAboveNearBottom() {
        // Two pointer-heights above the bottom edge: below is impossible.
        let pointer = CGPoint(x: 756, y: 20)
        let frame = AssistedPanelPlacement.frame(
            near: pointer, in: Self.visibleFrame, size: Self.size
        )

        #expect(frame.minY >= pointer.y)
        #expect(Self.visibleFrame.contains(frame))
    }

    @Test("The frame stays inside the visible frame on both axes")
    func clampedIntoVisibleFrame() {
        let pointers = [
            CGPoint(x: 10, y: 900),
            CGPoint(x: 1500, y: 900),
            CGPoint(x: 10, y: 500),
            CGPoint(x: 1500, y: 5),
        ]
        for pointer in pointers {
            let frame = AssistedPanelPlacement.frame(
                near: pointer, in: Self.visibleFrame, size: Self.size
            )
            #expect(
                Self.visibleFrame.contains(frame),
                "Panel \(frame) escapes \(Self.visibleFrame) for pointer \(pointer)"
            )
        }
    }

    @Test("A pointer on a secondary display placed to the left stays on it")
    func secondaryDisplayLeft() {
        // This side-by-side display starts right of the primary origin.
        let visibleFrame = CGRect(x: 1512, y: 0, width: 2560, height: 1339)
        let pointer = CGPoint(x: 1600, y: 700)
        let frame = AssistedPanelPlacement.frame(
            near: pointer, in: visibleFrame, size: Self.size
        )

        #expect(visibleFrame.contains(frame))
        #expect(!frame.contains(pointer))
    }
}
