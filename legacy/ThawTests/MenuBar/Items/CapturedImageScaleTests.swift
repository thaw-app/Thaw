//
//  CapturedImageScaleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers `MenuBarItemImageCache.resolvedScale(imagePixelWidth:boundsWidth:expected:)`,
/// shared by every capture path (#851, #736, #990).
///
/// On a 1x external beside a Retina display, SCK and SkyLight both return 2x
/// pixels, so an exact width check rejects every composite and the layout
/// editor shows gray placeholders.
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
        // #851: the display reported backingScaleFactor 1.0, but
        // ScreenCaptureKit captured at 2x.
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 1850, boundsWidth: 925, expected: 1)
                == 2
        )
    }

    @Test("The #990 composite strips resolve to the captured scale")
    func mixedScaleCompositeStripsResolve() {
        // #990: a 1x external next to a Retina one. SCK and SkyLight both
        // captured their strips at 2x.
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 1044, boundsWidth: 522, expected: 1)
                == 2
        )
        #expect(
            MenuBarItemImageCache.resolvedScale(imagePixelWidth: 10730, boundsWidth: 5365, expected: 1)
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
        // The tolerance covers widths that do not divide evenly.
        let scale = MenuBarItemImageCache.resolvedScale(
            imagePixelWidth: 45,
            boundsWidth: 22.6,
            expected: 2
        )
        #expect(scale == 2)
    }

    @Test("An implausible ratio is rejected rather than cached")
    func implausibleRatioIsRejected() {
        // Stale bounds or a mid-capture resize leave no safe scale, so the
        // item is dropped. A missing icon is recoverable; a mis-scaled one is not.
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
        // CapturedImage divides pixels by scale to get points, and the layout
        // bar sizes its rows from that. A wrong scale doubles the row height.
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
