//
//  CapturedImageScaleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers `MenuBarItemImageCache.resolvedScale(imagePixelWidth:boundsWidth:expected:)`,
/// the check `individualCapture` was missing in #851/#736.
///
/// `compositeCapture` and `refreshImages` both compare an image's pixel
/// width against `bounds.width * scale` and reject a mismatch.
/// `individualCapture` did not — and it is the path that runs *after*
/// `compositeCapture` rejects a capture, so the guard's own failure route
/// fed the bug. An image cached under the wrong scale makes every consumer
/// double the item's point size, which is the oversized Layout rows in the
/// report.
@Suite("Captured image scale resolution")
struct CapturedImageScaleTests {
    @Test("Agreement returns the expected scale unchanged")
    func agreementKeepsExpectedScale() {
        // 24pt item on a 2x display captured at 48px.
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 48, boundsWidth: 24, expected: 2)
                == 2
        )
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 24, boundsWidth: 24, expected: 1)
                == 1
        )
    }

    @Test("A 2x capture on a 1x display resolves to the captured scale")
    func mixedScaleCaptureUsesCapturedScale() {
        // The exact shape from the #851 log: the resolved display reported
        // backingScaleFactor 1.0, but ScreenCaptureKit captured at 2x
        // (compositeCapture logged "expected 925.0 ... but got 1850.0").
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 1850, boundsWidth: 925, expected: 1)
                == 2
        )
    }

    @Test("A 1x capture on a 2x display resolves to the captured scale")
    func reverseMismatchAlsoUsesCapturedScale() {
        // The same disagreement in the other direction, which happens when
        // the menu bar is resolved to the retina display but the items sit
        // on the external one.
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 24, boundsWidth: 24, expected: 2)
                == 1
        )
    }

    @Test("A 3x capture is accepted")
    func threeTimesIsPlausible() {
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 72, boundsWidth: 24, expected: 1)
                == 3
        )
    }

    @Test("Integer pixel rounding on narrow items still resolves")
    func roundingNoiseIsTolerated() {
        // 22.5pt at 2x rounds to 45px; the derived scale is exactly 2 here,
        // but 23pt -> 46px derives 2.0 and 21.5pt -> 43px derives exactly 2
        // as well. The tolerance covers the cases that do not divide evenly.
        let scale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: 45,
            boundsWidth: 22.6,
            expected: 2
        )
        #expect(scale == 2)
    }

    @Test("An implausible ratio is rejected rather than cached")
    func implausibleRatioIsRejected() {
        // Bounds and image describe different things — stale bounds, or a
        // window resized mid-capture. There is no safe scale to cache
        // under, so the item is dropped. A missing icon is recoverable;
        // a wrongly-scaled cached one is not.
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 100, boundsWidth: 24, expected: 1)
                == nil
        )
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 5, boundsWidth: 24, expected: 1)
                == nil
        )
    }

    @Test("Degenerate inputs are rejected")
    func degenerateInputsAreRejected() {
        // A zero-width item would divide by zero.
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 48, boundsWidth: 0, expected: 2)
                == nil
        )
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 0, boundsWidth: 24, expected: 2)
                == nil
        )
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 48, boundsWidth: -24, expected: 2)
                == nil
        )
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 48, boundsWidth: 24, expected: 0)
                == nil
        )
    }

    @Test("The resolved scale gives the item back its true point size")
    func resolvedScaleRestoresPointSize() {
        // The property that actually matters downstream: CapturedImage
        // divides pixels by scale to get points, and the layout bar sizes
        // its rows from that. Under the old behavior this produced 1850pt
        // instead of 925pt — the doubled row height in the screenshot.
        let boundsWidth: CGFloat = 925
        let pixelWidth = 1850

        let scale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: pixelWidth,
            boundsWidth: boundsWidth,
            expected: 1
        )

        let resolved = try? #require(scale)
        #expect(CGFloat(pixelWidth) / (resolved ?? 1) == boundsWidth)
    }
}
