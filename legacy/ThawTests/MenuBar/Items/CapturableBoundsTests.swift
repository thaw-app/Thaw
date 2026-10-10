//
//  CapturableBoundsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes which window bounds may take part in a composite capture.
///
/// `refreshImages` slices one composite by each window's offset in the bounds
/// union. The capture APIs drop zero-size windows, but a parked one still
/// widens the union, so the width check fails and the Hidden rows render empty.
@Suite("Capturable bounds")
struct CapturableBoundsTests {
    @Test("An ordinary menu bar item window is capturable")
    func ordinaryWindowIsCapturable() {
        #expect(MenuBarItemImageCache.isCapturableBounds(CGRect(x: 1242, y: 0, width: 42, height: 33)))
    }

    @Test("A zero-width window is not capturable")
    func zeroWidthIsNotCapturable() {
        // A degenerate window parked off-screen, as observed in the field.
        #expect(!MenuBarItemImageCache.isCapturableBounds(CGRect(x: -3774, y: 0, width: 0, height: 33)))
    }

    @Test("A zero-height window is not capturable")
    func zeroHeightIsNotCapturable() {
        #expect(!MenuBarItemImageCache.isCapturableBounds(CGRect(x: 1242, y: 0, width: 42, height: 0)))
    }

    @Test("A fully empty rect is not capturable")
    func emptyRectIsNotCapturable() {
        #expect(!MenuBarItemImageCache.isCapturableBounds(.zero))
        #expect(!MenuBarItemImageCache.isCapturableBounds(.null))
    }

    /// Seven on-screen items plus two degenerate windows at x=-3774, as in
    /// the field log.
    @Test("Degenerate windows no longer widen the batch union")
    func degenerateWindowsDoNotWidenTheUnion() {
        let real = [
            CGRect(x: 1242, y: 0, width: 42, height: 33),
            CGRect(x: 1284, y: 0, width: 33, height: 33),
            CGRect(x: 1317, y: 0, width: 34, height: 33),
            CGRect(x: 1351, y: 0, width: 33, height: 33),
            CGRect(x: 1384, y: 0, width: 38, height: 33),
            CGRect(x: 1422, y: 0, width: 38, height: 33),
            CGRect(x: 1460, y: 0, width: 42, height: 33),
        ]
        let degenerate = [
            CGRect(x: -3774, y: 0, width: 0, height: 33),
            CGRect(x: -3774, y: 0, width: 0, height: 33),
        ]

        let unfiltered = (real + degenerate).reduce(CGRect.null) { $0.union($1) }
        #expect(unfiltered.width == 5276) // what the guard used to compare against

        let filtered = (real + degenerate)
            .filter(MenuBarItemImageCache.isCapturableBounds)
            .reduce(CGRect.null) { $0.union($1) }
        #expect(filtered.width == 260)
        #expect(filtered.width * 2 == 520) // the composite the capture returns at 2x
    }
}
