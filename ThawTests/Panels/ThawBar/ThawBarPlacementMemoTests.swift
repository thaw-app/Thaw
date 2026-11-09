//
//  ThawBarPlacementMemoTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// A window keeps whole points, so a half-point content size never matched the panel's frame and
/// every layout pass resized and repositioned the Thaw Bar, logging the clamp each time.
@Suite("Thaw Bar placement memo")
struct ThawBarPlacementMemoTests {
    private let halfPointIdeal = CGSize(width: 576.5, height: 47)
    private let roundedFrame = CGSize(width: 577, height: 47)

    @Test("Content that matches the frame needs no resize, and new content does")
    func matchingContentIsLeftAlone() {
        let fit = ThawBarContentFit()
        #expect(!fit.needsResize(ideal: roundedFrame, frameSize: roundedFrame))
        #expect(fit.needsResize(ideal: halfPointIdeal, frameSize: .zero))
    }

    @Test("A half-point size the window rounded is fitted once, not on every layout pass")
    func roundedSizeIsFittedOnce() {
        var fit = ThawBarContentFit()
        #expect(fit.needsResize(ideal: halfPointIdeal, frameSize: CGSize(width: 531, height: 47)))
        fit.noteResize(ideal: halfPointIdeal, frameSize: roundedFrame)
        #expect(!fit.needsResize(ideal: halfPointIdeal, frameSize: roundedFrame))
    }

    @Test("Changed content, or a frame changed from elsewhere, is fitted again")
    func changesAreFittedAgain() {
        var fit = ThawBarContentFit()
        fit.noteResize(ideal: halfPointIdeal, frameSize: roundedFrame)
        #expect(fit.needsResize(ideal: CGSize(width: 530.5, height: 47), frameSize: roundedFrame))
        #expect(fit.needsResize(ideal: halfPointIdeal, frameSize: CGSize(width: 600, height: 47)))
    }

    @Test("A clamp is reported once per distinct value in one open, and again on the next open")
    func clampIsReportedOncePerOpen() {
        var report = ThawBarClampReport()
        let firstOpen = ContinuousClock.now
        let first = report.isNew(desiredX: 1004, clamped: 935, since: firstOpen)
        let repeated = report.isNew(desiredX: 1004, clamped: 935, since: firstOpen)
        let otherValue = report.isNew(desiredX: 1027, clamped: 981, since: firstOpen)
        let nextOpen = report.isNew(desiredX: 1027, clamped: 981, since: firstOpen.advanced(by: .seconds(5)))
        #expect(first)
        #expect(!repeated)
        #expect(otherValue)
        #expect(nextOpen)
    }

    @Test("A placement clamping moved by a point or less is never reported")
    func smallClampIsNotReported() {
        var report = ThawBarClampReport()
        let halfPoint = report.isNew(desiredX: 935.5, clamped: 935, since: nil)
        let unclamped = report.isNew(desiredX: 900, clamped: 900, since: nil)
        #expect(!halfPoint)
        #expect(!unclamped)
    }
}
