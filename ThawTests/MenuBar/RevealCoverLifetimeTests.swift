//
//  RevealCoverLifetimeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("Reveal cover lifetime")
struct RevealCoverLifetimeTests {
    @Test("A capture's cover outlives a batch whose last settle poll starts at the budget and reads a crowded bar")
    func captureCoverOutlivesBatch() {
        // One whole-bar read took up to 7 s with about 135 apps running.
        let slowestRead = Duration.seconds(7)
        let batch = Constants.MenuBarTuning.revealCaptureSettleBudget
            + slowestRead
            + Constants.MenuBarTuning.layoutPrewarmRenderSettle
        #expect(Constants.MenuBarTuning.revealCaptureCoverLifetime > batch)
    }

    @Test("A run that raised no cover drops its picture")
    func unusedPictureIsDropped() throws {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let cover = RevealCover()
        cover.pictures[1] = MenuBarBackdrop.Strip(rect: CGRect(x: 0, y: 0, width: 4, height: 4), image: image)

        cover.dropUnusedPictures()

        #expect(cover.pictures.isEmpty)
    }
}
