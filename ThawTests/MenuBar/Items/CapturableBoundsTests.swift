//
//  CapturableBoundsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes which window bounds may take part in a composite capture.
///
/// `refreshImages` captures a batch of item windows as one image and slices it
/// per item using each window's offset within the batch's bounds union. A
/// degenerate window — zero width or zero height — breaks that: the capture
/// APIs drop it from the composite, so it adds no pixels, while including it in
/// the union corrupts the geometry the composite gets sliced against. Parked
/// off-screen it widens the union across the whole gap, the composite's width
/// no longer matches, and the batch is discarded. That is the difference
/// between previews rendering and the Hidden rows appearing empty.
///
/// Which item produced the degenerate bounds does not matter to any of this.
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

    /// The regression itself, in the geometry the field log recorded: seven
    /// contiguous on-screen items plus two degenerate windows at x=-3774. With
    /// those filtered, the union matches the composite the capture returns
    /// (260pt → 520px at 2x); without them it is 5276pt wide and every batch is
    /// thrown away.
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
